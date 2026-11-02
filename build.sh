#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Pulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun clang -O2 -mmacosx-version-min=13.0 -c Sources/Bridge.c -o build/Bridge.o
xcrun swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 -import-objc-header Sources/Bridge.h Sources/Metrics.swift Sources/Dashboard.swift Sources/main.swift build/Bridge.o -framework Cocoa -framework SwiftUI -framework IOKit -framework ServiceManagement -o "$APP/Contents/MacOS/Pulse"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
cp Resources/ThirdPartyNotices.txt "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
print "Built: $APP"
