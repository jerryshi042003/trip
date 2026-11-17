#!/bin/zsh
# Build, sign and install Trip on Jerry's iPhone. Refreshes the bundled copy of trip.json first.
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
cd "$(dirname "$0")"
DEVICE=${DEVICE:-B68379E2-7FBD-5CF7-B616-B3BECC99873E}
TEAM=${TEAM:-39225XZQP2}
DD=${DD:-$HOME/Scratch/trip-dd}
cp ../docs/trip.json Trip/trip.json
xcodegen generate >/dev/null
xcodebuild -project Trip.xcodeproj -scheme Trip -destination 'generic/platform=iOS' \
  -derivedDataPath "$DD" -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build -quiet
xcrun devicectl device install app --device "$DEVICE" "$DD/Build/Products/Debug-iphoneos/Trip.app"
xcrun devicectl device process launch --device "$DEVICE" com.shishi88.trip
