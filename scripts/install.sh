#!/bin/bash
set -e

# Colors for terminal output
BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"
RESET="\033[0m"

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║                PLUME INSTALLER FOR MAC                ║${RESET}"
echo -e "${CYAN}${BOLD}║       Fast, Local AI Voice Dictation Assistant        ║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"
echo ""

# 1. Check macOS architecture
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86_64" ]; then
    echo -e "${RED}✗ Unsupported architecture: $ARCH. Plume requires macOS on Apple Silicon or Intel.${RESET}"
    exit 1
fi

# 2. Check for Homebrew & whisper-cpp
echo -e "${BLUE}▶ Checking dependencies...${RESET}"
WHISPER_PATH=""
for path in "/opt/homebrew/bin/whisper-cpp" "/usr/local/bin/whisper-cpp" "$(which whisper-cpp 2>/dev/null)"; do
    if [ -x "$path" ]; then
        WHISPER_PATH="$path"
        break
    fi
done

if [ -z "$WHISPER_PATH" ]; then
    echo -e "${YELLOW}! whisper-cpp not found. Installing via Homebrew...${RESET}"
    if ! command -v brew >/dev/null 2>&1; then
        echo -e "${RED}✗ Homebrew is not installed. Please install Homebrew first:${RESET}"
        echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        exit 1
    fi
    brew install whisper-cpp
    echo -e "${GREEN}✓ whisper-cpp installed successfully.${RESET}"
else
    echo -e "${GREEN}✓ whisper-cpp found at $WHISPER_PATH.${RESET}"
fi

# 3. Check for Swift / Xcode Command Line Tools
if ! command -v swift >/dev/null 2>&1; then
    echo -e "${YELLOW}! Xcode Command Line Tools not found. Installing...${RESET}"
    xcode-select --install
    echo -e "${YELLOW}Please complete the Xcode command line tools prompt and re-run this script.${RESET}"
    exit 1
fi
echo -e "${GREEN}✓ Swift compiler available.${RESET}"

# 4. Download Whisper AI Model (Multilingual)
MODELS_DIR="$HOME/.voiceflow/models"
mkdir -p "$MODELS_DIR"
MODEL_FILE="$MODELS_DIR/ggml-base.bin"

if [ ! -f "$MODEL_FILE" ] || [ $(wc -c < "$MODEL_FILE" 2>/dev/null || echo 0) -lt 100000000 ]; then
    echo -e "${BLUE}▶ Downloading high-speed Multilingual Whisper AI model (~141 MB)...${RESET}"
    curl -L --progress-bar "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin" -o "$MODEL_FILE.tmp"
    mv "$MODEL_FILE.tmp" "$MODEL_FILE"
    echo -e "${GREEN}✓ Speech model ready at $MODEL_FILE.${RESET}"
else
    echo -e "${GREEN}✓ Speech model already present.${RESET}"
fi

# 5. Build Plume Application
echo -e "${BLUE}▶ Building Plume from source...${RESET}"

TEMP_BUILD_DIR=""
# Check if we are inside the Plume repository
if [ -f "Package.swift" ] && grep -q "VoiceFlow" "Package.swift" 2>/dev/null; then
    SRC_DIR="$(pwd)"
else
    TEMP_BUILD_DIR=$(mktemp -d)
    echo -e "  Cloning latest repository..."
    git clone --depth 1 "https://github.com/Dakshx07/Plume.git" "$TEMP_BUILD_DIR"
    SRC_DIR="$TEMP_BUILD_DIR"
fi

cd "$SRC_DIR"
swift build -c release

# 6. Bundle Application into /Applications/Plume.app
APP_BUNDLE="/Applications/Plume.app"
echo -e "${BLUE}▶ Installing Plume to /Applications/Plume.app...${RESET}"

# Kill running instance if updating
killall Plume 2>/dev/null || true

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/VoiceFlow" "$APP_BUNDLE/Contents/MacOS/Plume"
cp "Sources/VoiceFlow/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "Sources/VoiceFlow/Resources/AppIcon.icns" ]; then
    cp "Sources/VoiceFlow/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

chmod +x "$APP_BUNDLE/Contents/MacOS/Plume"

# Clear stale TCC caches from earlier attempts
tccutil reset Accessibility com.dakshhiran.Plume 2>/dev/null || true
tccutil reset ListenEvent com.dakshhiran.Plume 2>/dev/null || true

# 7. Code Signing with persistent designated requirement
DEV_ID=$(security find-identity -p codesigning -v 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}' || true)
if [ -n "$DEV_ID" ]; then
    echo -e "  Signing with Developer Certificate: $DEV_ID"
    codesign --force --deep --sign "$DEV_ID" --identifier "com.dakshhiran.Plume" "$APP_BUNDLE"
else
    echo -e "  Signing with persistent local identifier..."
    codesign --force --deep -s - --identifier "com.dakshhiran.Plume" -r='designated => identifier "com.dakshhiran.Plume"' "$APP_BUNDLE"
fi
touch "$APP_BUNDLE"

# 8. Configure Auto-Start at Login (LaunchAgent)
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

# Clean up temp clone if used
if [ -n "$TEMP_BUILD_DIR" ]; then
    rm -rf "$TEMP_BUILD_DIR"
fi

# 9. Launch Plume
open "$APP_BUNDLE"

echo ""
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}✓ Plume successfully installed and launched!${RESET}"
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${BOLD}Next Steps:${RESET}"
echo -e "1. ${CYAN}Permissions:${RESET} When macOS asks, allow ${BOLD}Accessibility${RESET} & ${BOLD}Input Monitoring${RESET} in System Settings."
echo -e "2. ${CYAN}To Dictate:${RESET} Press ${BOLD}Control twice (⌃ ⌃)${RESET} anywhere, speak, and tap ${BOLD}⌃${RESET} once to type!"
echo -e "3. ${CYAN}Menu Bar:${RESET} Look for Flow the Bot mascot in your top menu bar."
echo ""
