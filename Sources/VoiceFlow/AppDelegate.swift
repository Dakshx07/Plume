import AppKit
import AVFoundation
import os.log

public enum AppState {
    case idle
    case recording
    case transcribing
    case processing
    case saving
    case error
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate, AudioRecorderDelegate {
    public static let shared = AppDelegate()

    private let logger = Config.logger
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!

    private let audioRecorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private let hotkeyManager = HotkeyManager()

    private(set) public var state: AppState = .idle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        setupMenuBar()
        setupAudioRecorder()
        setupHotkey()

        checkPrerequisites()

        logger.info("VoiceFlow launched successfully.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        audioRecorder.stopRecording()
        audioRecorder.cleanup()
    }

    private var menuStatusBadge: NSTextField?
    private var menuRecordItem: NSMenuItem?

    // MARK: - Menu Bar Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "VoiceFlow")
            img?.isTemplate = true
            button.image = img
            button.imagePosition = .imageOnly
        }

        let menu = NSMenu()

        // 1. Custom rich header item
        let headerItem = NSMenuItem()
        headerItem.view = createMenuHeaderView()
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Start / Stop Recording action item
        let recordItem = NSMenuItem(title: "Start Recording (⌥ Space)", action: #selector(toggleRecordingFromMenu), keyEquivalent: "")
        recordItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
        recordItem.target = self
        menu.addItem(recordItem)
        self.menuRecordItem = recordItem

        menu.addItem(NSMenuItem.separator())

        // 3. Settings & Permissions
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permsItem = NSMenuItem(title: "Check Permissions", action: #selector(checkPermissions), keyEquivalent: "p")
        permsItem.image = NSImage(systemSymbolName: "checkmark.shield", accessibilityDescription: "Permissions")
        permsItem.target = self
        menu.addItem(permsItem)

        menu.addItem(NSMenuItem.separator())

        // 4. About & Quit
        let aboutItem = NSMenuItem(title: "About VoiceFlow", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit VoiceFlow", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func createMenuHeaderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 50))

        let iconView = NSImageView(frame: NSRect(x: 14, y: 11, width: 28, height: 28))
        iconView.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "VoiceFlow")
        iconView.contentTintColor = .labelColor
        view.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "VoiceFlow")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.frame = NSRect(x: 50, y: 26, width: 90, height: 18)
        view.addSubview(titleLabel)

        let status = NSTextField(labelWithString: "● Ready")
        status.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        status.textColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 1.0)
        status.frame = NSRect(x: 50, y: 10, width: 95, height: 15)
        view.addSubview(status)
        self.menuStatusBadge = status

        let keycap = NSTextField(labelWithString: "⌥ Space")
        keycap.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold)
        keycap.textColor = .secondaryLabelColor
        keycap.alignment = .center
        keycap.wantsLayer = true
        keycap.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        keycap.layer?.cornerRadius = 4.0
        keycap.layer?.masksToBounds = true
        keycap.frame = NSRect(x: 152, y: 15, width: 66, height: 20)
        view.addSubview(keycap)

        return view
    }

    @objc private func toggleRecordingFromMenu() {
        hotkeyManagerDidTriggerToggle(hotkeyManager)
    }

    private func updateMenuStatus(text: String, isRecording: Bool = false) {
        if let button = statusItem.button {
            if isRecording {
                let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
                button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceFlow Recording")?.withSymbolConfiguration(config)
            } else {
                let img = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "VoiceFlow")
                img?.isTemplate = true
                button.image = img
            }
        }

        if isRecording {
            menuStatusBadge?.stringValue = "● Recording"
            menuStatusBadge?.textColor = .systemRed
            menuRecordItem?.title = "Stop Recording"
            menuRecordItem?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")
        } else {
            menuStatusBadge?.stringValue = "● Ready"
            menuStatusBadge?.textColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 1.0)
            menuRecordItem?.title = "Start Recording (⌥ Space)"
            menuRecordItem?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
        }
    }

    // MARK: - Audio & Hotkey Setup

    private func setupAudioRecorder() {
        audioRecorder.delegate = self
    }

    private func setupHotkey() {
        hotkeyManager.delegate = self
        // Delay 1.5 seconds to let system initialize before starting event tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hotkeyManager.start()
        }
    }

    // MARK: - Prerequisites Check

    private func checkPrerequisites() {
        if !Config.isWhisperInstalled {
            showNotification(
                title: "whisper.cpp not found",
                message: "whisper.cpp not found at /opt/homebrew/bin/whisper-cpp. Please verify installation."
            )
        }

        if !Config.isModelInstalled {
            showNotification(
                title: "Whisper Model Missing",
                message: "Model not found at \(Config.whisperModelPath). Please verify the model file."
            )
        }

        if !Permissions.shared.isAccessibilityGranted {
            logger.info("Accessibility permission not yet granted. Requesting...")
            Permissions.shared.requestAccessibility()
        }
    }

    // MARK: - HotkeyManagerDelegate

    public func hotkeyManagerDidTriggerToggle(_ manager: HotkeyManager) {
        switch state {
        case .idle:
            startRecordingSession()
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing, .processing, .saving, .error:
            logger.info("Hotkey pressed while app is busy (\(String(describing: self.state))). Ignoring.")
        }
    }

    // MARK: - Recording Flow

    private func startRecordingSession() {
        guard state == .idle else { return }

        // Check microphone permission
        guard Permissions.shared.isMicrophoneGranted else {
            Permissions.shared.requestMicrophone { [weak self] granted in
                guard let self = self else { return }
                if !granted {
                    self.showOverlayError("Microphone permission needed")
                    self.showNotification(
                        title: "Microphone Access Required",
                        message: "Please allow microphone access in System Settings for VoiceFlow."
                    )
                }
            }
            return
        }

        do {
            try audioRecorder.startRecording()
            state = .recording
            updateMenuStatus(text: "Status: 🔴 Recording...", isRecording: true)
            OverlayWindowController.shared.showListening()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            showOverlayError(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe() {
        guard state == .recording else { return }

        state = .transcribing
        updateMenuStatus(text: "Status: Finishing...", isRecording: false)
        // Flow the Bot pops out of the pill and starts wandering!
        OverlayWindowController.shared.startProcessing()

        guard let wavURL = audioRecorder.stopRecording() else {
            showOverlayError("Audio recording failed")
            return
        }

        Task {
            do {
                let transcript = try await transcriber.transcribe(audioFileURL: wavURL)
                await handleTranscriptionResult(transcript)
            } catch WhisperError.emptyTranscript {
                await MainActor.run {
                    self.logger.info("No speech detected.")
                    OverlayWindowController.shared.showError("No speech detected")
                    self.resetToIdleAfterDelay(0.4)
                }
            } catch {
                await MainActor.run {
                    self.logger.error("Transcription error: \(error.localizedDescription)")
                    OverlayWindowController.shared.showError(error.localizedDescription)
                    self.resetToIdleAfterDelay(0.4)
                }
            }
        }
    }

    // MARK: - AI & Output Handling

    private func handleTranscriptionResult(_ transcript: String) async {
        logger.info("Transcription completed successfully.")

        let isNotion = GeminiClient.shared.isNotionTrigger(in: transcript)

        if isNotion {
            await handleNotionFlow(transcript: transcript)
        } else {
            await handleDictationFlow(transcript: transcript)
        }
    }

    private func handleDictationFlow(transcript: String) async {
        await MainActor.run {
            self.state = .processing
            self.updateMenuStatus(text: "Status: Processing...")
        }

        var fallbackNotice: String?

        let cleanedText = await GeminiClient.shared.cleanDictation(rawTranscript: transcript) { reason in
            switch reason {
            case .keyNotSet:
                fallbackNotice = "Gemini key not set, typed raw text"
            case .unauthorized:
                fallbackNotice = "Gemini API key invalid, typed raw text"
            case .rateLimited:
                fallbackNotice = "Rate limited, typed raw text"
            case .networkError(let msg):
                fallbackNotice = "Network issue (\(msg)), typed raw text"
            case .emptyResponse, .parseError:
                fallbackNotice = "Could not clean speech, typed raw text"
            }
        }

        if let notice = fallbackNotice {
            await MainActor.run {
                self.showNotification(title: "VoiceFlow", message: notice)
            }
        }

        await MainActor.run {
            Permissions.shared.insertText(cleanedText) { [weak self] success in
                guard let self = self else { return }
                if success {
                    OverlayWindowController.shared.finishSuccess {
                        self.resetToIdleAfterDelay(1.2)
                    }
                } else {
                    OverlayWindowController.shared.showError("Insertion failed")
                    self.resetToIdleAfterDelay(0.8)
                }
            }
        }
    }

    private func handleNotionFlow(transcript: String) async {
        if !Config.isNotionConfigured {
            await MainActor.run {
                self.showNotification(
                    title: "Notion Not Configured",
                    message: "Notion API key or database ID not set. Typed text instead."
                )
            }
            await handleDictationFlow(transcript: transcript)
            return
        }

        await MainActor.run {
            self.state = .saving
            self.updateMenuStatus(text: "Status: Saving to Notion...")
        }

        let note = await GeminiClient.shared.extractNotionNote(rawTranscript: transcript)

        do {
            _ = try await NotionClient.shared.createPage(title: note.title, content: note.content)
            await MainActor.run {
                self.showNotification(title: "Saved to Notion", message: note.title)
                OverlayWindowController.shared.finishSuccess {
                    self.resetToIdleAfterDelay(1.2)
                }
            }
        } catch {
            await MainActor.run {
                self.logger.error("Notion save failed: \(error.localizedDescription). Falling back to typing text.")
                self.showNotification(
                    title: "Notion Save Failed",
                    message: "\(error.localizedDescription) — Typed text into active app."
                )
                Permissions.shared.insertText("\(note.title)\n\n\(note.content)")
                OverlayWindowController.shared.finishSuccess {
                    self.resetToIdleAfterDelay(1.2)
                }
            }
        }
    }

    // MARK: - State Resets & Overlays

    private func showOverlayError(_ message: String) {
        state = .error
        updateMenuStatus(text: "Status: Error")
        OverlayWindowController.shared.showError(message)
        resetToIdleAfterDelay(0.8)
    }

    private func resetToIdleAfterDelay(_ seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self = self else { return }
            self.state = .idle
            self.updateMenuStatus(text: "Status: Ready")
        }
    }

    // MARK: - AudioRecorderDelegate

    public func audioRecorder(_ recorder: AudioRecorder, didUpdateAudioLevel level: Float, dbLevel: Float) {
        OverlayWindowController.shared.updateAudioLevel(level)
    }

    public func audioRecorderDidDetectSilence(_ recorder: AudioRecorder) {
        guard self.state == .recording else { return }
        self.logger.info("AudioRecorder detected silence. Auto-stopping recording.")
        self.stopRecordingAndTranscribe()
    }

    public func audioRecorderDidReachMaxDuration(_ recorder: AudioRecorder) {
        guard self.state == .recording else { return }
        self.logger.info("AudioRecorder reached max duration. Stopping recording.")
        self.stopRecordingAndTranscribe()
    }

    public func audioRecorder(_ recorder: AudioRecorder, didFailWithError error: Error) {
        self.logger.error("Audio recording failed with error: \(error.localizedDescription)")
        self.audioRecorder.stopRecording()
        self.showOverlayError(error.localizedDescription)
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
    }

    @objc private func checkPermissions() {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.updatePermissionsStatus()
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About VoiceFlow"
        alert.informativeText = """
        VoiceFlow is a fast, offline-first voice dictation tool for macOS.

        • Option + Space: Tap to start / stop recording
        • Local speech-to-text via whisper.cpp
        • Cloud Hinglish cleanup via Gemini 2.0 Flash
        • Direct saving to Notion

        Version 1.0.0
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Notifications

    public func showNotification(title: String, message: String) {
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedMsg = message.replacingOccurrences(of: "\"", with: "\\\"")

        let script = "display notification \"\(escapedMsg)\" with title \"\(escapedTitle)\" sound name \"default\""
        DispatchQueue.global(qos: .utility).async {
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
        }
    }
}
