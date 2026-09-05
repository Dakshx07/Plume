import AppKit

public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()

    // Gemini API Key inputs (Secure with toggleable Eye button)
    private var geminiSecureField: NSSecureTextField!
    private var geminiPlainField: NSTextField!
    private var eyeButton: NSButton!
    private var isKeyRevealed = false

    /*
    // MARK: - Notion Integration (Commented out for now per user request)
    private var notionKeyField: NSSecureTextField!
    private var notionDbField: NSTextField!
    */

    private var configStatusLabel: NSTextField!
    private var axStatusBadge: NSTextField!
    private var micStatusBadge: NSTextField!
    private var inputStatusBadge: NSTextField!

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 490),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Plume Settings"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        loadSettings()
        updatePermissionsStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setupUI() {
        guard let window = self.window else { return }

        let contentView = NSView(frame: window.contentView!.bounds)
        window.contentView = contentView

        var currentY: CGFloat = 436

        // Header: App branding & subtitle
        let iconBadge = NSImageView(frame: NSRect(x: 24, y: currentY - 2, width: 32, height: 32))
        iconBadge.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "VoiceFlow")
        iconBadge.contentTintColor = .labelColor
        contentView.addSubview(iconBadge)

        let titleLabel = NSTextField(labelWithString: "Plume Preferences")
        titleLabel.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        titleLabel.frame = NSRect(x: 64, y: currentY + 8, width: 380, height: 20)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Configure AI speech enhancement and system permissions")
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.frame = NSRect(x: 64, y: currentY - 8, width: 380, height: 16)
        contentView.addSubview(subtitleLabel)

        currentY -= 36

        // Divider
        let sep0 = NSBox(frame: NSRect(x: 24, y: currentY, width: 432, height: 1))
        sep0.boxType = .separator
        contentView.addSubview(sep0)

        currentY -= 20

        // CARD 1: AI Model Provider (Gemini)
        let geminiCardHeight: CGFloat = 120
        let geminiCard = createCardView(frame: NSRect(x: 24, y: currentY - geminiCardHeight, width: 432, height: geminiCardHeight))
        contentView.addSubview(geminiCard)

        let geminiSectionLabel = NSTextField(labelWithString: "AI SPEECH ENHANCEMENT")
        geminiSectionLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        geminiSectionLabel.textColor = .secondaryLabelColor
        geminiSectionLabel.frame = NSRect(x: 16, y: geminiCardHeight - 24, width: 250, height: 14)
        geminiCard.addSubview(geminiSectionLabel)

        let geminiDescLabel = NSTextField(labelWithString: "Google Gemini 2.5 Flash for Hinglish cleanup, formatting & grammar.")
        geminiDescLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        geminiDescLabel.textColor = .secondaryLabelColor
        geminiDescLabel.frame = NSRect(x: 16, y: geminiCardHeight - 42, width: 400, height: 15)
        geminiCard.addSubview(geminiDescLabel)

        // Secure Key Field (bullets)
        geminiSecureField = NSSecureTextField(frame: NSRect(x: 16, y: geminiCardHeight - 74, width: 362, height: 26))
        geminiSecureField.placeholderString = "Paste Gemini API Key (AIza...)"
        geminiSecureField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        geminiCard.addSubview(geminiSecureField)

        // Plaintext Key Field (revealed on eye click, hidden by default)
        geminiPlainField = NSTextField(frame: NSRect(x: 16, y: geminiCardHeight - 74, width: 362, height: 26))
        geminiPlainField.placeholderString = "Paste Gemini API Key (AIza...)"
        geminiPlainField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        geminiPlainField.isHidden = true
        geminiCard.addSubview(geminiPlainField)

        // Eye Toggle Button
        eyeButton = NSButton(frame: NSRect(x: 386, y: geminiCardHeight - 74, width: 30, height: 26))
        eyeButton.bezelStyle = .rounded
        eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Toggle visibility")
        eyeButton.imagePosition = .imageOnly
        eyeButton.target = self
        eyeButton.action = #selector(toggleKeyVisibility)
        geminiCard.addSubview(eyeButton)

        // Link to get free Gemini key
        let linkBtn = createLinkButton(
            title: "Get free API key: aistudio.google.com/apikey ↗",
            url: "https://aistudio.google.com/apikey",
            frame: NSRect(x: 16, y: geminiCardHeight - 104, width: 320, height: 18)
        )
        geminiCard.addSubview(linkBtn)

        /*
        // MARK: - Notion Fields UI (Commented out for now per user request)
        let notionKeyLabel = NSTextField(labelWithString: "Notion API Key:")
        notionKeyField = NSSecureTextField(frame: NSRect(x: 16, y: 0, width: 362, height: 24))
        notionDbField = NSTextField(frame: NSRect(x: 16, y: 0, width: 362, height: 24))
        */

        currentY -= (geminiCardHeight + 16)

        // CARD 2: macOS Permissions Status
        let permCardHeight: CGFloat = 132
        let permCard = createCardView(frame: NSRect(x: 24, y: currentY - permCardHeight, width: 432, height: permCardHeight))
        contentView.addSubview(permCard)

        let permHeaderLabel = NSTextField(labelWithString: "SYSTEM PERMISSIONS")
        permHeaderLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        permHeaderLabel.textColor = .secondaryLabelColor
        permHeaderLabel.frame = NSRect(x: 16, y: permCardHeight - 24, width: 250, height: 14)
        permCard.addSubview(permHeaderLabel)

        let checkPermBtn = NSButton(frame: NSRect(x: 290, y: permCardHeight - 28, width: 126, height: 22))
        checkPermBtn.title = "Verify Permissions"
        checkPermBtn.bezelStyle = .rounded
        checkPermBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        checkPermBtn.target = self
        checkPermBtn.action = #selector(checkPermissionsClicked)
        permCard.addSubview(checkPermBtn)

        // Row 1: Accessibility
        let axLabel = NSTextField(labelWithString: "Accessibility")
        axLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        axLabel.frame = NSRect(x: 16, y: permCardHeight - 52, width: 120, height: 16)
        permCard.addSubview(axLabel)

        let axDesc = NSTextField(labelWithString: "Required to paste transcribed text into active applications")
        axDesc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        axDesc.textColor = .secondaryLabelColor
        axDesc.frame = NSRect(x: 16, y: permCardHeight - 68, width: 300, height: 14)
        permCard.addSubview(axDesc)

        axStatusBadge = createBadge(frame: NSRect(x: 334, y: permCardHeight - 62, width: 82, height: 20))
        permCard.addSubview(axStatusBadge)

        // Row 2: Microphone
        let micLabel = NSTextField(labelWithString: "Microphone")
        micLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        micLabel.frame = NSRect(x: 16, y: permCardHeight - 92, width: 120, height: 16)
        permCard.addSubview(micLabel)

        let micDesc = NSTextField(labelWithString: "Required for capturing voice input locally")
        micDesc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        micDesc.textColor = .secondaryLabelColor
        micDesc.frame = NSRect(x: 16, y: permCardHeight - 108, width: 300, height: 14)
        permCard.addSubview(micDesc)

        micStatusBadge = createBadge(frame: NSRect(x: 334, y: permCardHeight - 102, width: 82, height: 20))
        permCard.addSubview(micStatusBadge)

        // Row 3: Input Monitoring
        let inLabel = NSTextField(labelWithString: "Input Monitoring")
        inLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        inLabel.frame = NSRect(x: 16, y: permCardHeight - 132, width: 120, height: 16)
        permCard.addSubview(inLabel)

        inputStatusBadge = createBadge(frame: NSRect(x: 334, y: permCardHeight - 138, width: 82, height: 20))
        permCard.addSubview(inputStatusBadge)

        currentY -= (permCardHeight + 16)

        // CARD 3: Quick Guide / Global Shortcut
        let shortcutCardHeight: CGFloat = 46
        let shortcutCard = createCardView(frame: NSRect(x: 24, y: currentY - shortcutCardHeight, width: 432, height: shortcutCardHeight))
        contentView.addSubview(shortcutCard)

        let keycapPill = NSTextField(labelWithString: "⌥ Option + Space")
        keycapPill.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        keycapPill.textColor = .labelColor
        keycapPill.alignment = .center
        keycapPill.wantsLayer = true
        keycapPill.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        keycapPill.layer?.cornerRadius = 5
        keycapPill.layer?.masksToBounds = true
        keycapPill.frame = NSRect(x: 14, y: 12, width: 130, height: 22)
        shortcutCard.addSubview(keycapPill)

        let shortcutDesc = NSTextField(labelWithString: "Tap anywhere to start dictation; tap again to finish & paste.")
        shortcutDesc.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        shortcutDesc.textColor = .secondaryLabelColor
        shortcutDesc.frame = NSRect(x: 154, y: 14, width: 264, height: 18)
        shortcutCard.addSubview(shortcutDesc)

        currentY -= (shortcutCardHeight + 20)

        // Footer: Save Button & Status Feedback
        let saveButton = NSButton(frame: NSRect(x: 24, y: currentY, width: 120, height: 30))
        saveButton.title = "Save Settings"
        saveButton.bezelStyle = .rounded
        saveButton.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        contentView.addSubview(saveButton)

        configStatusLabel = NSTextField(labelWithString: "")
        configStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        configStatusLabel.frame = NSRect(x: 154, y: currentY + 5, width: 302, height: 20)
        contentView.addSubview(configStatusLabel)
    }

    private func createCardView(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 10.0
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        return card
    }

    private func createBadge(frame: NSRect) -> NSTextField {
        let badge = NSTextField(labelWithString: "Checking...")
        badge.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4.0
        badge.layer?.masksToBounds = true
        badge.frame = frame
        return badge
    }

    private func setBadgeState(_ badge: NSTextField, isGranted: Bool, grantedText: String = "Granted", requiredText: String = "Required") {
        if isGranted {
            badge.stringValue = "✓ \(grantedText)"
            badge.textColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 1.0)
            badge.layer?.backgroundColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 0.12).cgColor
        } else {
            badge.stringValue = "! \(requiredText)"
            badge.textColor = .systemOrange
            badge.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.12).cgColor
        }
    }

    private func createLinkButton(title: String, url: String, frame: NSRect) -> NSButton {
        let button = NSButton(frame: frame)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 11)
        button.contentTintColor = .linkColor

        let pstyle = NSMutableParagraphStyle()
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 11),
                .paragraphStyle: pstyle
            ]
        )
        button.attributedTitle = attributedTitle
        button.target = self
        button.action = #selector(openURLFromButton(_:))
        button.identifier = NSUserInterfaceItemIdentifier(url)
        return button
    }

    @objc private func toggleKeyVisibility() {
        isKeyRevealed.toggle()
        if isKeyRevealed {
            geminiPlainField.stringValue = geminiSecureField.stringValue
            geminiSecureField.isHidden = true
            geminiPlainField.isHidden = false
            window?.makeFirstResponder(geminiPlainField)
            eyeButton.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: "Hide Key")
        } else {
            geminiSecureField.stringValue = geminiPlainField.stringValue
            geminiPlainField.isHidden = true
            geminiSecureField.isHidden = false
            window?.makeFirstResponder(geminiSecureField)
            eyeButton.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Reveal Key")
        }
    }

    @objc private func openURLFromButton(_ sender: NSButton) {
        guard let urlString = sender.identifier?.rawValue, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func saveSettings() {
        let currentKey = isKeyRevealed ? geminiPlainField.stringValue : geminiSecureField.stringValue
        Config.geminiAPIKey = currentKey

        /*
        // Notion save commented out for now per user request
        Config.notionAPIKey = notionKeyField.stringValue
        Config.notionDatabaseID = notionDbField.stringValue
        */

        configStatusLabel.stringValue = "✅ Saved!"
        configStatusLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.updateConfigStatus()
        }
    }

    private func loadSettings() {
        let key = Config.geminiAPIKey
        geminiSecureField.stringValue = key
        geminiPlainField.stringValue = key

        /*
        // Notion load commented out for now per user request
        notionKeyField.stringValue = Config.notionAPIKey
        notionDbField.stringValue = Config.notionDatabaseID
        */

        updateConfigStatus()
    }

    private func updateConfigStatus() {
        let currentKey = isKeyRevealed ? geminiPlainField.stringValue : geminiSecureField.stringValue
        let hasGemini = !currentKey.isEmpty

        if hasGemini {
            configStatusLabel.stringValue = "✅ Gemini active and ready"
            configStatusLabel.textColor = NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.35, alpha: 1.0)
        } else {
            configStatusLabel.stringValue = "⚠️ Gemini API key required"
            configStatusLabel.textColor = .systemOrange
        }
    }

    @objc private func checkPermissionsClicked() {
        if !Permissions.shared.isAccessibilityGranted {
            Permissions.shared.requestAccessibility()
        }
        if !Permissions.shared.isInputMonitoringGranted {
            Permissions.shared.requestInputMonitoring()
        }
        if !Permissions.shared.isMicrophoneGranted {
            Permissions.shared.requestMicrophone { [weak self] _ in
                self?.updatePermissionsStatus()
            }
        }
        updatePermissionsStatus()
    }

    public func updatePermissionsStatus() {
        let ax = Permissions.shared.isAccessibilityGranted
        let mic = Permissions.shared.isMicrophoneGranted
        let input = Permissions.shared.isInputMonitoringGranted

        setBadgeState(axStatusBadge, isGranted: ax)
        setBadgeState(micStatusBadge, isGranted: mic)
        setBadgeState(inputStatusBadge, isGranted: input, grantedText: "Active")
    }
}
