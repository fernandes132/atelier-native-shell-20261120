#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
mkdir -p build/Payload/Atelier.app
APP="$PWD/build/Payload/Atelier.app"
xcrun swiftc -parse-as-library -O -target arm64-apple-ios16.0 -sdk "$SDK" -framework UIKit -framework WebKit -framework Network App.swift -o "$APP/Atelier"
cp Info.plist "$APP/Info.plist"
cp Icon.png "$APP/Icon.png"
# Only copy web resources if provided; the free native-only build omits private assets.
if [[ -d ../web ]]; then cp -R ../web "$APP/web"; fi
codesign --force --sign - "$APP"
cd build
zip -qry Atelier-iPhone-unsigned.ipa Payload
