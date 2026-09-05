<div align="center">

# 🪶 Plume

**The living, lightning-fast voice dictation and in-place AI editing engine for macOS.**

[![macOS](https://img.shields.io/badge/macOS-13.0%2B-blue?logo=apple&style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift&style=flat-square)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

*Speak naturally. Edit in place. Live with a companion.*

</div>

---

## ✨ What is Plume?

**Plume** is a native macOS voice productivity companion designed for speed, beauty, and delight. Instead of standard corporate dictation or heavy local models that drain battery, Plume delivers a zero-overhead, sub-second typing experience powered by on-device Metal acceleration, Google Gemini Flash, and **Flow the Bot**—a living, expressive mascot who lives in your menu bar and floating pill.

### 🌟 Key Highlights

- **⚡ Sub-Millisecond UI**: Press your hotkey and the pill appears on screen in $< 20$ms. Zero wait, zero hesitation.
- **🤖 Flow the Living Mascot**: An expressive, physics-animated bot with expressive programmatic eyes, natural breathing, spontaneous blinking, in-place head tilts ($\pm 8^\circ$), speech cadence nodding, and celebratory reactions.
- **✨ In-Place Voice Editing (`Shift + Option + Space`)**: Highlight text in *any* Mac application (Xcode, VS Code, Notes, Slack, Browser), speak your command (*"make it professional"*, *"convert to Swift Codable"*, *"fix grammar"*), and watch it transform in place.
- **📋 Voice Clipboard Transformation**: Speak commands to instantly summarize, extract info from, or format whatever is in your clipboard.
- **🏎️ Ultra-Fast Dictation Pipeline**: High-performance Apple Silicon Metal speech transcription paired with Gemini Flash post-processing delivers clean, formatted English in ~1.0 second.
- **🔋 Zero Background LLM Overhead**: No heavy 10GB local models draining RAM or battery. Runs completely lightweight as a silent macOS menu bar process.
- **🎨 Flawless Mac Aesthetics**: Jet-black glassmorphic pill, crisp hairline border, 100% transparent anti-aliased corners, zero text distraction.

---

## ⌨️ Shortcuts

| Shortcut | Action | Description |
| :--- | :--- | :--- |
| **`⌥ Space`** *(Option + Space)* | **Dictate** | Speak naturally; Plume transcribes, cleans grammar/fillers, and pastes at your cursor. |
| **`⇧ ⌥ Space`** *(Shift + Option + Space)* | **Transform** | Edits highlighted text in-place using your spoken command, or transforms your clipboard. |

---

## 🛠️ Architecture & Tech Stack

Plume is built with 100% native Apple technologies:

- **Language**: Swift 5.9+
- **Frameworks**: AppKit, QuartzCore, AVFoundation (CoreAudio / AUVoiceIO), ApplicationServices (Accessibility API)
- **Speech Engine**: Apple Silicon Metal-accelerated `whisper.cpp`
- **AI Transformation**: Google Gemini Flash API
- **Display Pipeline**: Direct Single-Surface CoreGraphics with hardware-accelerated CALayer transforms

---

## 🚀 Getting Started

### Prerequisites

- macOS 13.0 (Ventura) or newer (optimized for Apple Silicon M1/M2/M3/M4)
- `whisper-cpp` (via Homebrew):
  ```bash
  brew install whisper-cpp
  ```

### Build & Run

1. Clone the repository:
   ```bash
   git clone https://github.com/Dakshx07/Plume.git
   cd Plume
   ```

2. Build the release binary:
   ```bash
   swift build -c release
   ```

3. Launch Plume:
   ```bash
   ./.build/release/VoiceFlow
   ```

---

## 🔒 Permissions

Plume requires standard macOS permissions to deliver its seamless experience:
- **Microphone**: For audio recording and speech recognition.
- **Accessibility**: For instant text insertion and reading highlighted text in-place.
- **Input Monitoring**: For global hotkey detection (`⌥ Space` and `⇧ ⌥ Space`).

All audio processing happens on-device and through your configured API keys. No voice data is ever collected or tracked.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) — see the LICENSE file for details.
