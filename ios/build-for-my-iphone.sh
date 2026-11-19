#!/bin/zsh
# Build Trip from source and install it on the iPhone plugged into this Mac.
# Works for anyone with a Mac, Xcode and a free Apple Account:
#   git clone https://github.com/jerryshi042003/trip && trip/ios/build-for-my-iphone.sh
# Optional: TEAM=<team id>  DEVICE=<device id>  BUNDLE_ID=<bundle id>
set -euo pipefail
cd "$(dirname "$0")"
say() { print -P "%B$1%b" }
fail() { print -P "%F{red}%B$1%b%f"; exit 1 }

# Xcode
if [[ -z ${DEVELOPER_DIR:-} ]]; then
  dev=$(xcode-select -p 2>/dev/null || true)
  if [[ $dev != *Xcode*.app* ]]; then
    app=$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1)
    [[ -n $app ]] || fail "Install Xcode from the Mac App Store, open it once, then run this again."
    export DEVELOPER_DIR=$app/Contents/Developer
  fi
fi

# XcodeGen (downloaded once if Homebrew's copy is missing)
XG=$(command -v xcodegen || true)
if [[ -z $XG ]]; then
  XG=$HOME/.cache/trip-xcodegen/xcodegen/bin/xcodegen
  if [[ ! -x $XG ]]; then
    say "Downloading XcodeGen (one time)…"
    mkdir -p ~/.cache/trip-xcodegen && cd ~/.cache/trip-xcodegen
    curl -fsSL -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip
    unzip -oq xcodegen.zip && cd - >/dev/null
  fi
fi

# Signing team: the Apple Development certificate Xcode made when you signed in
if [[ -z ${TEAM:-} ]]; then
  TEAM=$(security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
  [[ -n $TEAM ]] || fail "Open Xcode → Settings → Accounts, add your Apple Account, click Manage Certificates → + → Apple Development. Then run this again."
fi
# Jerry's team owns com.shishi88.trip; everyone else gets their own copy
if [[ -z ${BUNDLE_ID:-} ]]; then
  [[ $TEAM == 39225XZQP2 ]] && BUNDLE_ID=com.shishi88.trip || BUNDLE_ID=com.shishi88.trip.$TEAM:l
fi

# iPhone: the first one connected by cable or Wi-Fi
if [[ -z ${DEVICE:-} ]]; then
  xcrun devicectl list devices --json-output /tmp/trip-devices.$$.json >/dev/null 2>&1 || true
  DEVICE=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))["result"]["devices"]
d=[x for x in d if x["hardwareProperties"].get("platform")=="iOS" and x["connectionProperties"].get("pairingState")=="paired"]
d.sort(key=lambda x: x["connectionProperties"].get("tunnelState")=="unavailable")
print(d[0]["identifier"] if d else "")' /tmp/trip-devices.$$.json 2>/dev/null || true)
  rm -f /tmp/trip-devices.$$.json
  [[ -n $DEVICE ]] || fail "Plug in your iPhone, unlock it and tap Trust. First time only: iPhone Settings → Privacy & Security → Developer Mode → On."
fi

DD=${DD:-$HOME/Library/Caches/trip-build}
say "Building Trip (team $TEAM, app id $BUNDLE_ID)…"
cp ../docs/trip.json Trip/trip.json
"$XG" generate --quiet
xcodebuild -project Trip.xcodeproj -scheme Trip -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build -quiet
say "Installing on your iPhone…"
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Release-iphoneos/Trip.app" >/dev/null \
  || fail "Couldn't reach your iPhone. Plug it in with a cable, unlock it, then run this again (it rebuilds in seconds)."
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 \
  || say "Installed. If iPhone says Untrusted Developer: Settings → General → VPN & Device Management → your Apple Account → Trust."
say "Done. Trip is on your iPhone."
