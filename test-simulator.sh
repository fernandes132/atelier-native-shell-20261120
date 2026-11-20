#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
APP="$PWD/build/Smoke.app"
mkdir -p "$APP/web"
xcrun swiftc -parse-as-library -D SIMULATOR_SMOKE -target "$(uname -m)-apple-ios18.0-simulator" -sdk "$SDK" -framework UIKit -framework WebKit -framework Network App.swift -o "$APP/Atelier"
cp Info.plist "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CFBundleSupportedPlatforms' "$APP/Info.plist" || true
cp Icon.png "$APP/Icon.png"
cp smoke.html "$APP/web/index.html"
codesign --force --sign - "$APP"
UDID=$(xcrun simctl list devices available -j | python3 -c 'import sys,json;d=json.load(sys.stdin);print(next(x["udid"] for a in d["devices"].values() for x in a if x["isAvailable"] and x["name"].startswith("iPhone")))')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" nl.atelier.studio
CONTAINER=$(xcrun simctl get_app_container "$UDID" nl.atelier.studio data)
for i in $(seq 1 90); do
 if [[ -f "$CONTAINER/Documents/container-smoke.json" ]]; then
  cp "$CONTAINER/Documents/container-smoke.json" build/container-smoke.json
  cat build/container-smoke.json
  python3 -c 'import json;assert json.load(open("build/container-smoke.json"))["pass"]'
  exit 0
 fi
 sleep 2
done
echo 'Native simulator smoke test timed out' >&2
exit 1
