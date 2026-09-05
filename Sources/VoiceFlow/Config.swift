import Foundation
import os.log

public enum Config {
    // MARK: - App Identity
    public static let appName = "Plume"
    public static let bundleIdentifier = "com.dakshhiran.Plume"

    // MARK: - Logger
    public static let logger = Logger(subsystem: "com.dakshhiran.plume", category: "App")

    // MARK: - UserDefaults Keys
    public enum Keys {
        public static let geminiAPIKey = "com.voiceflow.geminiAPIKey"
        public static let notionAPIKey = "com.voiceflow.notionAPIKey"
        public static let notionDatabaseID = "com.voiceflow.notionDatabaseID"
    }

    // MARK: - Secrets Accessors
    public static var geminiAPIKey: String {
        get {
            UserDefaults.standard.string(forKey: Keys.geminiAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.geminiAPIKey)
        }
    }

    public static var notionAPIKey: String {
        get {
            UserDefaults.standard.string(forKey: Keys.notionAPIKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.notionAPIKey)
        }
    }

    public static var notionDatabaseID: String {
        get {
            UserDefaults.standard.string(forKey: Keys.notionDatabaseID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.notionDatabaseID)
        }
    }

    public static var isNotionConfigured: Bool {
        return !notionAPIKey.isEmpty && !notionDatabaseID.isEmpty
    }

    // MARK: - Binary & Model Paths
    public static let preferredWhisperBinaryPath = "/opt/homebrew/bin/whisper-cpp"
    private static let candidateWhisperPaths = [
        "/opt/homebrew/bin/whisper-cpp",
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cpp",
        "/usr/local/bin/whisper-cli"
    ]

    public static var resolvedWhisperBinaryPath: String? {
        for path in candidateWhisperPaths {
            if FileManager.default.fileExists(atPath: path) && FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    public static var whisperModelPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let baseMultiPath = "\(home)/.voiceflow/models/ggml-base.bin"
        if FileManager.default.fileExists(atPath: baseMultiPath) {
            return baseMultiPath
        }
        let baseEnPath = "\(home)/.voiceflow/models/ggml-base.en.bin"
        if FileManager.default.fileExists(atPath: baseEnPath) {
            return baseEnPath
        }
        let turboPath = "\(home)/.voiceflow/models/ggml-large-v3-turbo.bin"
        if FileManager.default.fileExists(atPath: turboPath) {
            return turboPath
        }
        return baseMultiPath
    }

    public static var isWhisperInstalled: Bool {
        return resolvedWhisperBinaryPath != nil
    }

    public static var isModelInstalled: Bool {
        return FileManager.default.fileExists(atPath: whisperModelPath)
    }

    // MARK: - Audio Configuration
    public enum Audio {
        public static let sampleRate: Double = 16000.0
        public static let channelCount: UInt32 = 1
        public static let silenceThresholdDB: Float = -35.0
        public static let silenceDurationSeconds: TimeInterval = 1.20
        public static let minRecordingDurationSeconds: TimeInterval = 0.5
        public static let maxRecordingDurationSeconds: TimeInterval = 120.0
    }

    // MARK: - Hotkey Configuration
    public enum Hotkey {
        public static let controlHoldDurationSeconds: TimeInterval = 1.10
        public static let debounceIntervalSeconds: TimeInterval = 0.22
    }
}

import AppKit

// MARK: - VoiceFlow Design System Colors
public extension NSColor {
    static let vfBackground = NSColor(calibratedWhite: 0.11, alpha: 1.0) // #1C1C1E
    static let vfTextPrimary = NSColor.white
    static let vfTextSecondary = NSColor.white.withAlphaComponent(0.60)
    static let vfRecording = NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1.0) // #FF453A
    static let vfSuccess = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)   // #30D158
    static let vfError = NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)     // #FF453A
    static let vfProcessing = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0) // #0A84FF
    static let vfNotion = NSColor.white
}

// MARK: - Typography
public enum VFFont {
    public static let overlayStatus = NSFont.systemFont(ofSize: 13, weight: .medium)
    public static let menuBarStatus = NSFont.systemFont(ofSize: 13, weight: .regular)
    public static let settingsSection = NSFont.systemFont(ofSize: 15, weight: .semibold)
    public static let settingsLabel = NSFont.systemFont(ofSize: 13, weight: .regular)
    public static let settingsHelper = NSFont.systemFont(ofSize: 11, weight: .regular)
}

// MARK: - Spacing & Layout Constants
public enum VFSpacing {
    public static let overlayWidthRecording: CGFloat = 260
    public static let overlayWidthProcessing: CGFloat = 220
    public static let overlayWidthSaving: CGFloat = 240
    public static let overlayWidthSuccess: CGFloat = 220
    public static let overlayWidthError: CGFloat = 260
    public static let overlayHeight: CGFloat = 52
    public static let overlayCornerRadius: CGFloat = 26 // height / 2
    public static let overlayBottomMargin: CGFloat = 40 // distance from bottom of screen
    public static let overlayInternalPadding: CGFloat = 16
    public static let overlayElementSpacing: CGFloat = 10

    public static let waveformWidth: CGFloat = 40
    public static let waveformHeight: CGFloat = 28
    public static let waveformBarCount: Int = 5
    public static let waveformBarWidth: CGFloat = 3
    public static let waveformBarSpacing: CGFloat = 5
    public static let waveformBarMinHeight: CGFloat = 4
    public static let waveformBarMaxHeight: CGFloat = 24
    public static let waveformBarCornerRadius: CGFloat = 1.5

    public static let spinnerSize: CGFloat = 18
    public static let iconSize: CGFloat = 18
    public static let statusTextWidth: CGFloat = 140
}
