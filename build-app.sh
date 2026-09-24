#!/bin/zsh
# Recompila el código y deja AutoVlogs.app lista en esta carpeta.
set -e
cd "$(dirname "$0")"
swift build -c release
app=AutoVlogs.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/VlogForge "$app/Contents/MacOS/AutoVlogs"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDisplayName</key><string>AutoVlogs</string>
<key>CFBundleExecutable</key><string>AutoVlogs</string>
<key>CFBundleIdentifier</key><string>local.autovlogs.app</string>
<key>CFBundleName</key><string>AutoVlogs</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app"
echo "Listo: $(pwd)/$app"
