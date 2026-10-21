#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/swift-module-cache"
swift build --disable-sandbox --configuration release --product ColimaDesk
APP_PATH="$PROJECT_ROOT/dist/Colima View.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp .build/release/ColimaDesk "$APP_PATH/Contents/MacOS/ColimaDesk.next"
mv -f "$APP_PATH/Contents/MacOS/ColimaDesk.next" "$APP_PATH/Contents/MacOS/ColimaDesk"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ColimaDesk</string>
<key>CFBundleIdentifier</key><string>dev.local.ColimaDesk</string>
<key>CFBundleName</key><string>Colima View</string>
<key>CFBundleDisplayName</key><string>Colima View</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
xcrun swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/create-icon.swift "$PROJECT_ROOT/.build/AppIcon.iconset"
iconutil --convert icns "$PROJECT_ROOT/.build/AppIcon.iconset" --output "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R .build/release/ColimaDesk_ColimaCore.bundle "$APP_PATH/Contents/Resources/"
xattr -cr "$APP_PATH"
codesign --force --sign - --identifier dev.local.ColimaDesk "$APP_PATH"
codesign --verify --strict "$APP_PATH"
printf '\nBuilt: %s\n' "$APP_PATH"
