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

# Sign with universal designated requirement so every Mac shares the exact same identity
echo "Signing with universal designated requirement..."
codesign --force --deep -s - --identifier "com.dakshhiran.PlumeApp" -r='designated => identifier "com.dakshhiran.PlumeApp"' "$APP_BUNDLE"

touch "$APP_BUNDLE"

# Configure LaunchAgent for auto-start at login
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.dakshhiran.plumeapp.plist"
mkdir -p "$LAUNCH_AGENTS_DIR"

cat <<EOF > "$PLIST_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.dakshhiran.PlumeApp</string>
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
