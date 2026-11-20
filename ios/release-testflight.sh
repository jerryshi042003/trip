#!/bin/zsh
# Ship a new Trip build to TestFlight in one command (Jerry's Mac, team 39225XZQP2).
#   ios/release-testflight.sh
# Bumps CURRENT_PROJECT_VERSION in project.yml, archives, uploads to App Store Connect,
# then commits and pushes the bump. "Trip internal" gets the build automatically once
# Apple finishes processing (usually 5-15 minutes).
# Auth: the Apple Account signed in to Xcode (Settings -> Accounts). Optional instead:
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/path/AuthKey_XXXX.p8
set -euo pipefail
cd "$(dirname "$0")"
say() { print -P "%B$1%b" }
fail() { print -P "%F{red}%B$1%b%f"; exit 1 }
TEAM=${TEAM:-39225XZQP2}

# Xcode
if [[ -z ${DEVELOPER_DIR:-} ]]; then
  dev=$(xcode-select -p 2>/dev/null || true)
  if [[ $dev != *Xcode*.app* ]]; then
    app=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1)
    [[ -n $app ]] || fail "Xcode not found in /Applications."
    export DEVELOPER_DIR=$app/Contents/Developer
  fi
fi

# XcodeGen
XG=$(command -v xcodegen || true)
if [[ -z $XG ]]; then
  XG=$HOME/.cache/trip-xcodegen/xcodegen/bin/xcodegen
  if [[ ! -x $XG ]]; then
    mkdir -p ~/.cache/trip-xcodegen
    curl -fsSL -o ~/.cache/trip-xcodegen/xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip
    (cd ~/.cache/trip-xcodegen && unzip -oq xcodegen.zip)
  fi
fi

# Start from the latest main so the build number never collides
[[ -z $(git status --porcelain -- project.yml) ]] || fail "ios/project.yml has uncommitted changes. Commit or discard them first."
git pull --no-rebase -q

OLD=$(sed -n "s/^ *CURRENT_PROJECT_VERSION: *'\{0,1\}\([0-9]*\)'\{0,1\}.*/\1/p" project.yml | head -1)
[[ -n $OLD ]] || fail "Couldn't read CURRENT_PROJECT_VERSION from project.yml."
NEW=$(( OLD + 1 ))
sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: *\)'\{0,1\}$OLD'\{0,1\}/\1'$NEW'/" project.yml
say "Building Trip build $NEW (was $OLD)…"

WORK=${WORK:-$HOME/Library/Caches/trip-release}
LOG=${LOG:-$HOME/Library/Logs/trip-release.log}
rm -rf "$WORK" && mkdir -p "$WORK" "$(dirname "$LOG")"
: > "$LOG"
print "Full log: $LOG"
restore() { [[ ${SHIPPED:-0} == 1 ]] || git checkout -q -- project.yml; rm -rf "$WORK" }
trap restore EXIT

AUTH=()
if [[ -n ${ASC_KEY_ID:-} ]]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" -authenticationKeyPath "$ASC_KEY_PATH")
fi

cp ../docs/trip.json Trip/trip.json
"$XG" generate --quiet
xcodebuild -project Trip.xcodeproj -scheme Trip -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Trip.xcarchive" -derivedDataPath "$WORK/dd" -allowProvisioningUpdates "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$TEAM" archive >> "$LOG" 2>&1 || { tail -30 "$LOG"; fail "Archive failed. Full log: $LOG"; }

cat > "$WORK/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>uploadSymbols</key><true/>
</dict></plist>
EOF
say "Uploading build $NEW to App Store Connect…"
xcodebuild -exportArchive -archivePath "$WORK/Trip.xcarchive" -exportOptionsPlist "$WORK/export.plist" \
  -exportPath "$WORK/export" -allowProvisioningUpdates "${AUTH[@]}" >> "$LOG" 2>&1 || true
grep -E "Upload succeeded|EXPORT|error:" "$LOG" | tail -5
grep -q "Upload succeeded" "$LOG" || fail "Upload failed. Is your Apple Account signed in to Xcode (Settings -> Accounts)?"

SHIPPED=1
git add project.yml Trip/trip.json
git commit -q -m "TestFlight build $NEW"
git pull --no-rebase -q && git push -q
say "Done. Build $NEW uploaded. It appears in TestFlight -> Trip internal after Apple processes it (5-15 min)."
