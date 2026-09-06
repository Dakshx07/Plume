#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "Building Plume (Release)..."
swift build -c release

APP_NAME="Plume.app"
INSTALL_DIR="/Applications"
APP_BUNDLE="$INSTALL_DIR/$APP_NAME"

echo "Bundling $APP_NAME into $INSTALL_DIR..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/VoiceFlow" "$APP_BUNDLE/Contents/MacOS/Plume"
cp "Sources/VoiceFlow/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "Sources/VoiceFlow/Resources/AppIcon.icns" ]; then
    cp "Sources/VoiceFlow/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

chmod +x "$APP_BUNDLE/Contents/MacOS/Plume"

# Detect Developer Identity for permanent TCC permissions
DEV_ID=$(security find-identity -p codesigning -v | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}')
if [ -n "$DEV_ID" ]; then
    echo "Signing with Developer Identity: $DEV_ID"
    codesign --force --deep --sign "$DEV_ID" --identifier "com.dakshhiran.Plume" "$APP_BUNDLE"
else
    echo "Signing ad-hoc with designated requirement..."
    codesign --force --deep --sign - --identifier "com.dakshhiran.Plume" "$APP_BUNDLE"
fi

touch "$APP_BUNDLE"

# Configure LaunchAgent for auto-start at login
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.dakshhiran.plume.plist"
mkdir -p "$LAUNCH_AGENTS_DIR"

cat <<EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dakshhiran.plume</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_BUNDLE/Contents/MacOS/Plume</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

mkdir -p dist
rm -f dist/Plume.zip
(cd /Applications && zip -q -r "$DIR/dist/Plume.zip" "Plume.app")

echo "✓ Plume installed successfully at $APP_BUNDLE"
echo "✓ Pre-built dist/Plume.zip updated"
echo "✓ LaunchAgent configured at $PLIST_FILE"
echo "Plume is now ready to run automatically whenever you log into your Mac!"
