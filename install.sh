#!/bin/bash
set -e

BOLD="\033[1m"
GREEN="\033[32m"
BLUE="\033[34m"
YELLOW="\033[33m"
CYAN="\033[36m"
RESET="\033[0m"

echo ""
echo -e "${CYAN}${BOLD}╔═══════════════════════════════════════════════════════╗${RESET}"
echo -e "${CYAN}${BOLD}║                PLUME INSTALLER FOR MAC                ║${RESET}"
echo -e "${CYAN}${BOLD}║       Fast, Local AI Voice Dictation Assistant        ║${RESET}"
echo -e "${CYAN}${BOLD}╚═══════════════════════════════════════════════════════╝${RESET}"
echo ""

# 1. Architecture Check
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86_64" ]; then
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 2. Check / Install whisper-cpp
echo -e "${BLUE}▶ [1/4] Checking speech engine (whisper-cpp)...${RESET}"
WHISPER_PATH=""
for path in "/opt/homebrew/bin/whisper-cpp" "/usr/local/bin/whisper-cpp" "$(which whisper-cpp 2>/dev/null)"; do
    if [ -x "$path" ]; then
        WHISPER_PATH="$path"
        break
    fi
done

if [ -z "$WHISPER_PATH" ]; then
    echo -e "${YELLOW}! Installing whisper-cpp via Homebrew...${RESET}"
    if ! command -v brew >/dev/null 2>&1; then
        echo -e "${YELLOW}Installing Homebrew first...${RESET}"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
    brew install whisper-cpp
    echo -e "${GREEN}✓ whisper-cpp installed.${RESET}"
else
    echo -e "${GREEN}✓ whisper-cpp ready.${RESET}"
fi

# 3. Download AI Speech Model
MODELS_DIR="$HOME/.voiceflow/models"
mkdir -p "$MODELS_DIR"
MODEL_FILE="$MODELS_DIR/ggml-base.en.bin"

if [ ! -f "$MODEL_FILE" ] || [ $(wc -c < "$MODEL_FILE" 2>/dev/null || echo 0) -lt 100000000 ]; then
    echo -e "${BLUE}▶ [2/4] Downloading high-speed AI speech model (~141 MB)...${RESET}"
    curl -L --progress-bar "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin" -o "$MODEL_FILE.tmp"
    mv "$MODEL_FILE.tmp" "$MODEL_FILE"
    echo -e "${GREEN}✓ Speech model ready.${RESET}"
else
    echo -e "${GREEN}✓ Speech model already present.${RESET}"
fi

# 4. Download & Install Plume.app
echo -e "${BLUE}▶ [3/4] Installing Plume.app to /Applications...${RESET}"
killall Plume 2>/dev/null || true

TMP_ZIP="/tmp/Plume.zip"
rm -f "$TMP_ZIP"
rm -rf "/Applications/Plume.app"

# If running locally from repo with dist/Plume.zip present:
if [ -f "dist/Plume.zip" ]; then
    cp "dist/Plume.zip" "$TMP_ZIP"
else
    # Download pre-built app bundle directly from GitHub
    curl -L --progress-bar "https://raw.githubusercontent.com/Dakshx07/Plume/main/dist/Plume.zip" -o "$TMP_ZIP"
fi

unzip -q -o "$TMP_ZIP" -d "/Applications"
rm -f "$TMP_ZIP"

# Clear quarantine flags and ensure execution permissions
xattr -cr "/Applications/Plume.app" 2>/dev/null || true
chmod +x "/Applications/Plume.app/Contents/MacOS/Plume"

# Code sign with local identity or persistent ad-hoc requirement
DEV_ID=$(security find-identity -p codesigning -v 2>/dev/null | grep "Apple Development" | head -n 1 | awk -F'"' '{print $2}' || true)
if [ -n "$DEV_ID" ]; then
    codesign --force --deep --sign "$DEV_ID" --identifier "com.dakshhiran.Plume" "/Applications/Plume.app" 2>/dev/null || true
else
    codesign --force --deep --sign - --identifier "com.dakshhiran.Plume" "/Applications/Plume.app" 2>/dev/null || true
fi

# 5. Configure Auto-Start at Login
echo -e "${BLUE}▶ [4/4] Configuring auto-start...${RESET}"
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
        <string>/Applications/Plume.app/Contents/MacOS/Plume</string>
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

# 6. Launch Plume
open "/Applications/Plume.app"

echo ""
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}${BOLD}✓ Plume successfully installed and running!${RESET}"
echo -e "${GREEN}${BOLD}═══════════════════════════════════════════════════════${RESET}"
echo ""
echo -e "${BOLD}How to use:${RESET}"
echo -e "1. ${CYAN}Permissions:${RESET} Allow ${BOLD}Accessibility${RESET} & ${BOLD}Input Monitoring${RESET} when macOS prompts."
echo -e "2. ${CYAN}Dictate:${RESET} Press ${BOLD}Control twice (⌃ ⌃)${RESET} anywhere, speak, and tap ${BOLD}⌃${RESET} once to type!"
echo -e "3. ${CYAN}Menu Bar:${RESET} Look for Flow the Bot mascot in your top menu bar."
echo ""
