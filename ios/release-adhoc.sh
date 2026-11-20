#!/bin/zsh
# Rebuild the ad hoc Trip app and republish it at https://jerryshi042003.github.io/trip/install/
#   ios/release-adhoc.sh
# Anyone whose iPhone is registered on Jerry's team (39225XZQP2) then gets the new code by
# tapping Install again. iPhones are registered from the IDs shared on the install page:
#   - with ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH set, this script registers them itself;
#   - otherwise add them at https://developer.apple.com/account/resources/devices/add
# Uses the build number in project.yml as is (TestFlight releases bump it).
set -euo pipefail
cd "$(dirname "$0")"
say() { print -P "%B$1%b" }
fail() { print -P "%F{red}%B$1%b%f"; exit 1 }
TEAM=${TEAM:-39225XZQP2}
BUNDLE_ID=com.shishi88.trip
PAGES=https://jerryshi042003.github.io/trip/install

if [[ -z ${DEVELOPER_DIR:-} ]]; then
  dev=$(xcode-select -p 2>/dev/null || true)
  [[ $dev == *Xcode*.app* ]] || export DEVELOPER_DIR=$(ls -d /Applications/Xcode*.app | sort | tail -1)/Contents/Developer
fi
XG=$(command -v xcodegen || echo $HOME/.cache/trip-xcodegen/xcodegen/bin/xcodegen)
[[ -x $XG ]] || fail "XcodeGen missing: run ios/build-for-my-iphone.sh once first."

git pull --no-rebase -q
WORK=${WORK:-$HOME/Library/Caches/trip-adhoc}
LOG=${LOG:-$HOME/Library/Logs/trip-adhoc.log}
rm -rf "$WORK" && mkdir -p "$WORK" "$(dirname "$LOG")"
: > "$LOG"
trap 'rm -rf "$WORK"' EXIT
print "Full log: $LOG"

# Shared iPhone IDs (private Blob store, read with Vercel's token; nothing is written to the repo)
say "iPhones that shared their ID:"
[[ -d ../node_modules/@vercel/blob ]] || (cd .. && npm install --silent --no-audit --no-fund >> "$LOG" 2>&1)
if (cd .. && vercel env pull --yes --environment=production "$WORK/.env" >> "$LOG" 2>&1); then
  (set -a; source "$WORK/.env"; set +a; cd .. && node ios/adhoc-devices.mjs) || print "Couldn't read the device list (see log)."
else
  print "Couldn't reach Vercel; skipping the device list."
fi
rm -f "$WORK/.env"

AUTH=()
[[ -n ${ASC_KEY_ID:-} ]] && AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")

cp ../docs/trip.json Trip/trip.json
"$XG" generate --quiet
BUILD=$(sed -n "s/^ *CURRENT_PROJECT_VERSION: *'\{0,1\}\([0-9]*\)'\{0,1\}.*/\1/p" project.yml | head -1)
VERSION=$(sed -n "s/^ *MARKETING_VERSION: *'\{0,1\}\([0-9.]*\)'\{0,1\}.*/\1/p" project.yml | head -1)
say "Building ad hoc Trip $VERSION ($BUILD)…"
xcodebuild -project Trip.xcodeproj -scheme Trip -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Trip.xcarchive" -derivedDataPath "$WORK/dd" -allowProvisioningUpdates "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$TEAM" archive >> "$LOG" 2>&1 || { tail -30 "$LOG"; fail "Archive failed. Full log: $LOG"; }

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>release-testing</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM</string>
<key>compileBitcode</key><false/>
<key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
EOF
xcodebuild -exportArchive -archivePath "$WORK/Trip.xcarchive" -exportOptionsPlist "$WORK/export.plist" \
  -exportPath "$WORK/export" -allowProvisioningUpdates "${AUTH[@]}" >> "$LOG" 2>&1 \
  || { tail -30 "$LOG"; fail "Export failed. Full log: $LOG"; }
IPA=$(ls "$WORK"/export/*.ipa | head -1)

# How many devices the ad hoc profile covers (count only; IDs stay out of the repo)
unzip -p "$IPA" 'Payload/*.app/embedded.mobileprovision' | security cms -D 2>/dev/null > "$WORK/profile.plist" || true
COUNT=$(/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$WORK/profile.plist" 2>/dev/null | grep -c -- '-' || true)

cp "$IPA" ../docs/install/Trip.ipa
cat > ../docs/install/manifest.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>items</key><array><dict>
<key>assets</key><array>
<dict><key>kind</key><string>software-package</string><key>url</key><string>$PAGES/Trip.ipa?b=$BUILD-$(date +%s)</string></dict>
<dict><key>kind</key><string>display-image</string><key>url</key><string>$PAGES/icon-57.png</string></dict>
<dict><key>kind</key><string>full-size-image</string><key>url</key><string>$PAGES/icon-512.png</string></dict>
</array>
<key>metadata</key><dict>
<key>bundle-identifier</key><string>$BUNDLE_ID</string>
<key>bundle-version</key><string>$VERSION.$BUILD</string>
<key>kind</key><string>software</string>
<key>title</key><string>Trip</string>
</dict></dict></array></dict></plist>
EOF

cd ..
git add docs/install/Trip.ipa docs/install/manifest.plist
git commit -q -m "Ad hoc Trip build $BUILD for $COUNT iPhones" || true
git pull --no-rebase -q && git push -q
say "Done. Ad hoc build $BUILD covers $COUNT registered iPhones. Live at $PAGES/ once GitHub Pages publishes (about 1 min)."
