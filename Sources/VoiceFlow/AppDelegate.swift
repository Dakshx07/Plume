import AppKit
import AVFoundation
import UserNotifications
import os.log

public enum AppState {
    case idle
    case recording
    case transcribing
    case processing
    case saving
    case error
}

public enum SessionMode {
    case dictate
    case transform(contextText: String, isClipboard: Bool)
}

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, HotkeyManagerDelegate, AudioRecorderDelegate {
    public static let shared = AppDelegate()

    private let logger = Config.logger
    private var statusItem: NSStatusItem!
    private var miniBotView: BotView?
    private var menuStatusBadge: NSTextField?
    private var menuRecordItem: NSMenuItem?

    private let audioRecorder = AudioRecorder()
    private let transcriber = WhisperTranscriber()
    private let hotkeyManager = HotkeyManager()

    private(set) public var state: AppState = .idle
    private var sessionMode: SessionMode = .dictate

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        setupMenuBar()
        setupAudioRecorder()
        setupHotkey()

        checkPrerequisites()

        logger.info("Plume launched successfully.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
        audioRecorder.stopRecording()
        audioRecorder.cleanup()
    }

    // MARK: - Menu Bar Setup (Flow the Bot Living Status Item)

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 30.0)

        if let button = statusItem.button {
            button.subviews.forEach { $0.removeFromSuperview() }
            let miniBot = BotView(frame: NSRect(x: 3, y: 1, width: 24, height: 22))
            miniBot.startMenuBarCompanionMode()
            button.addSubview(miniBot)
            self.miniBotView = miniBot
        }

        let menu = NSMenu()

        // 1. Custom rich header item
        let headerItem = NSMenuItem()
        headerItem.view = createMenuHeaderView()
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // 2. Start / Stop Recording action item
        let recordItem = NSMenuItem(title: "Dictate (Hold Control ~1s)", action: #selector(toggleRecordingFromMenu), keyEquivalent: "")
        recordItem.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")
        recordItem.target = self
        menu.addItem(recordItem)
        self.menuRecordItem = recordItem

        let transformItem = NSMenuItem(title: "Transform Selection (Hold ⇧ Control ~1s)", action: #selector(toggleTransformFromMenu), keyEquivalent: "")
        transformItem.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Transform")
        transformItem.target = self
        menu.addItem(transformItem)

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
        let aboutItem = NSMenuItem(title: "About Plume", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit Plume", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func createMenuHeaderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 50))

        let iconView = NSImageView(frame: NSRect(x: 14, y: 11, width: 28, height: 28))
        iconView.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "Plume")
        iconView.contentTintColor = .labelColor
        view.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Plume")
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
        if state == .idle {
            startSession(action: .dictate)
        } else if state == .recording {
            stopRecordingAndTranscribe()
        }
    }

    @objc private func toggleTransformFromMenu() {
        if state == .idle {
            startSession(action: .transform)
        } else if state == .recording {
            stopRecordingAndTranscribe()
        }
    }

    private func updateMenuStatus(text: String, isRecording: Bool = false) {
        if isRecording {
            miniBotView?.stopMenuBarCompanionMode()
            miniBotView?.stopSpinning()
            miniBotView?.setExpression(.amazed, animated: true)
            miniBotView?.setRotation(degrees: -5.0, animated: true)
            menuStatusBadge?.stringValue = "● Recording"
            menuStatusBadge?.textColor = .systemRed
            menuRecordItem?.title = "Stop Recording"
            menuRecordItem?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop")
        } else {
            menuRecordItem?.title = "Dictate (Hold Control ~1s)"
            menuRecordItem?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Record")

            switch state {
            case .idle:
                miniBotView?.stopSpinning()
                miniBotView?.setExpression(.attentive, animated: true)
                miniBotView?.startMenuBarCompanionMode()
                menuStatusBadge?.stringValue = "● Ready"
                menuStatusBadge?.textColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 1.0)
            case .transcribing, .processing, .saving:
                miniBotView?.stopMenuBarCompanionMode()
                miniBotView?.setExpression(.thinking, animated: true)
                miniBotView?.startSpinning()
                menuStatusBadge?.stringValue = "● Processing..."
                menuStatusBadge?.textColor = .systemOrange
            case .error:
                miniBotView?.stopMenuBarCompanionMode()
                miniBotView?.stopSpinning()
                miniBotView?.setExpression(.surprised, animated: true)
                menuStatusBadge?.stringValue = "● Error"
                menuStatusBadge?.textColor = .systemRed
            default:
                break
            }
        }
    }

    // MARK: - Audio & Hotkey Setup

    private func setupAudioRecorder() {
        audioRecorder.delegate = self
        audioRecorder.prewarm()
    }

    private func setupHotkey() {
        hotkeyManager.delegate = self
        // Delay 1.0 second to let system initialize before starting event tap
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
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

    public func hotkeyManagerDidTriggerAction(_ manager: HotkeyManager, action: HotkeyAction) {
        switch state {
        case .idle:
            startSession(action: action)
        case .recording:
            stopRecordingAndTranscribe()
        case .transcribing, .processing, .saving, .error:
            logger.info("Hotkey pressed while app is busy (\(String(describing: self.state))). Ignoring.")
        }
    }

    // MARK: - Recording Flow

    private func startSession(action: HotkeyAction) {
        guard state == .idle else { return }

        // Check for Selection / Clipboard mode
        var mode: SessionMode = .dictate
        if action == .transform {
            if let selected = Permissions.shared.captureSelectedText() {
                mode = .transform(contextText: selected, isClipboard: false)
            } else if let clip = Permissions.shared.captureClipboardText() {
                mode = .transform(contextText: clip, isClipboard: true)
            }
        } else {
            // Option+Space: If user already highlighted text in active app, auto-transform it!
            if let selected = Permissions.shared.captureSelectedText() {
                mode = .transform(contextText: selected, isClipboard: false)
            }
        }
        self.sessionMode = mode

        let isTransform: Bool
        switch mode {
        case .transform: isTransform = true
        case .dictate: isTransform = false
        }

        // 1. Show UI INSTANTLY (< 15ms)
        OverlayWindowController.shared.showListening(isTransform: isTransform)
        state = .recording
        hotkeyManager.isRecording = true
        updateMenuStatus(text: "Status: Recording...", isRecording: true)

        // 2. Start audio capture (engine is already pre-warmed)
        guard Permissions.shared.isMicrophoneGranted else {
            Permissions.shared.requestMicrophone { [weak self] granted in
                guard let self = self else { return }
                if !granted {
                    self.showOverlayError("Microphone permission needed")
                }
            }
            return
        }

        do {
            try audioRecorder.startRecording()
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            showOverlayError(error.localizedDescription)
        }
    }

    private func stopRecordingAndTranscribe() {
        guard state == .recording else { return }

        state = .transcribing
        hotkeyManager.isRecording = false
        updateMenuStatus(text: "Status: Finishing...", isRecording: false)
        // Flow the Bot takes the full pill stage and begins its in-pill playground!
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
        logger.info("Transcription completed successfully: \(transcript)")

        switch sessionMode {
        case .transform(let contextText, let isClipboard):
            await handleTransformFlow(contextText: contextText, instruction: transcript, isClipboard: isClipboard)
        case .dictate:
            let isNotion = GeminiClient.shared.isNotionTrigger(in: transcript)
            if isNotion {
                await handleNotionFlow(transcript: transcript)
            } else {
                await handleDictationFlow(transcript: transcript)
            }
        }
    }

    private func handleTransformFlow(contextText: String, instruction: String, isClipboard: Bool) async {
        await MainActor.run {
            self.state = .processing
            self.updateMenuStatus(text: "Status: Transforming...")
        }

        let transformed = await GeminiClient.shared.transformText(contextText: contextText, instruction: instruction)

        await MainActor.run {
            if isClipboard {
                // Update system clipboard
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transformed, forType: .string)
            }

            // Replace selected text in place (or paste transformed clipboard)
            Permissions.shared.replaceSelectedText(transformed) { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.miniBotView?.stopSpinning()
                    self.miniBotView?.spinPirouette(revolutions: 2)
                    self.miniBotView?.setExpression(.happy, animated: true)
                    self.miniBotView?.squish()
                    OverlayWindowController.shared.finishSuccess {
                        self.resetToIdleAfterDelay(1.0)
                    }
                } else {
                    OverlayWindowController.shared.showError("Transform insertion failed")
                    self.resetToIdleAfterDelay(0.8)
                }
            }
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
                self.showNotification(title: "Plume", message: notice)
            }
        }

        await MainActor.run {
            Permissions.shared.insertText(cleanedText) { [weak self] success in
                guard let self = self else { return }
                if success {
                    self.miniBotView?.stopSpinning()
                    self.miniBotView?.spinPirouette(revolutions: 2)
                    self.miniBotView?.setExpression(.happy, animated: true)
                    self.miniBotView?.squish()
                    OverlayWindowController.shared.finishSuccess {
                        self.resetToIdleAfterDelay(1.0)
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
                    self.resetToIdleAfterDelay(1.0)
                }
            }
        } catch {
            await MainActor.run {
                self.logger.error("Notion save failed: \(error.localizedDescription). Falling back to typing text.")
                self.showNotification(
                    title: "Notion Save Failed",
                    message: "\(error.localizedDescription). Typed text instead."
                )
            }
            await handleDictationFlow(transcript: transcript)
        }
    }

    // MARK: - AudioRecorderDelegate

    public func audioRecorder(_ recorder: AudioRecorder, didUpdateAudioLevel level: Float, dbLevel: Float) {
        OverlayWindowController.shared.updateAudioLevel(level)
    }

    public func audioRecorderDidDetectSilence(_ recorder: AudioRecorder) {
        logger.info("AudioRecorder detected silence. Auto-stopping session.")
        stopRecordingAndTranscribe()
    }

    public func audioRecorderDidReachMaxDuration(_ recorder: AudioRecorder) {
        logger.info("AudioRecorder reached max duration. Stopping session.")
        stopRecordingAndTranscribe()
    }

    public func audioRecorder(_ recorder: AudioRecorder, didFailWithError error: Error) {
        logger.error("AudioRecorder failed: \(error.localizedDescription)")
        showOverlayError(error.localizedDescription)
    }

    // MARK: - Error & Notification Helpers

    private func showOverlayError(_ message: String) {
        state = .error
        updateMenuStatus(text: "Status: Error")
        OverlayWindowController.shared.showError(message)
        resetToIdleAfterDelay(2.0)
    }

    private func resetToIdleAfterDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.state = .idle
            self.hotkeyManager.isRecording = false
            self.sessionMode = .dictate
            self.updateMenuStatus(text: "Status: Ready")
        }
    }

    public func showNotification(title: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Menu Actions

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
    }

    @objc private func checkPermissions() {
        let mic = Permissions.shared.isMicrophoneGranted ? "✓ Granted" : "✗ Missing"
        let acc = Permissions.shared.isAccessibilityGranted ? "✓ Granted" : "✗ Missing"
        let inp = Permissions.shared.isInputMonitoringGranted ? "✓ Granted" : "✗ Missing"

        let message = """
        Microphone: \(mic)
        Accessibility: \(acc)
        Input Monitoring: \(inp)
        """

        let alert = NSAlert()
        alert.messageText = "Plume Permissions"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            openSettings()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "About Plume"
        alert.informativeText = """
        Plume v1.0.0
        The living, lightning-fast voice dictation and in-place AI editing engine for macOS.

        Shortcuts:
        • ⌥ Space: Dictate
        • ⇧ ⌥ Space: In-Place Transform Selection / Clipboard
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
