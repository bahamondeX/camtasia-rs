#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/CamtasiaRS.app/Contents/MacOS .cache/clang
cargo build --offline --release --target aarch64-apple-darwin -j 2
common=(-swift-version 5 -target arm64-apple-macosx15.0 -module-cache-path "$PWD/.cache/clang" -import-objc-header desktop/EditorCore.h desktop/CoreBridge.swift desktop/MediaEngine.swift target/aarch64-apple-darwin/release/libcamtasia_core.a -framework AVFoundation -framework CoreMedia -framework AppKit)
swiftc "${common[@]}" desktop/EditorApp.swift -framework SwiftUI -framework AVKit -framework UniformTypeIdentifiers -o build/CamtasiaRS.app/Contents/MacOS/CamtasiaRS
swiftc "${common[@]}" desktop/Validation.swift -o build/validate
cat > build/CamtasiaRS.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CamtasiaRS</string>
<key>CFBundleIdentifier</key><string>dev.camtasia-rs.editor</string>
<key>CFBundleName</key><string>Camtasia RS</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - build/CamtasiaRS.app
echo "Built build/CamtasiaRS.app and build/validate"
