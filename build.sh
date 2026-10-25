#!/bin/sh
# Builds build/Lumi Connect.app (ad-hoc signed).
set -e
cd "$(dirname "$0")"
APP="build/Lumi Connect.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/AppIcon.iconset

swiftc -O -swift-version 5 Sources/main.swift -o "$APP/Contents/MacOS/LumiConnect"
cp Info.plist "$APP/Contents/Info.plist"

swiftc -swift-version 5 Sources/make_icon.swift -o build/make_icon
build/make_icon build/icon_1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_1024.png --out "build/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"
