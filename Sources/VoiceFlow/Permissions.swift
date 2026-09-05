import AppKit
import AVFoundation
import ApplicationServices
import Carbon.HIToolbox
import os.log

public final class Permissions {
    public static let shared = Permissions()
    private let logger = Config.logger

    private init() {}

    // MARK: - Permission Checks

    public var isAccessibilityGranted: Bool {
        return AXIsProcessTrusted()
    }

    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public var isInputMonitoringGranted: Bool {
        return CGPreflightListenEventAccess()
    }

    public func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    public var isMicrophoneGranted: Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func requestMicrophone(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Open System Settings

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Text Insertion

    public func insertText(_ text: String, completion: ((Bool) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(true)
            return
        }

        if text.count > 10000 {
            logger.warning("Attempting to insert very large text (\(text.count) chars).")
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Primary method: Clipboard + Cmd+V
            let pasteSuccess = self.pasteViaClipboard(text)
            if pasteSuccess {
                DispatchQueue.main.async {
                    completion?(true)
                }
                return
            }

            self.logger.warning("Clipboard paste failed or accessibility not permitted. Trying AXUIElement.")

            // Secondary method: AXUIElement
            let axSuccess = self.insertViaAccessibility(text)
            if axSuccess {
                DispatchQueue.main.async {
                    completion?(true)
                }
                return
            }

            self.logger.warning("AXUIElement failed. Falling back to Unicode typing.")

            // Tertiary method: CGEvent Unicode typing
            let typingSuccess = self.typeViaUnicodeEvents(text)
            DispatchQueue.main.async {
                completion?(typingSuccess)
            }
        }
    }

    // MARK: - Primary: Clipboard + Cmd+V

    private struct SavedPasteboardItem {
        let typesData: [(NSPasteboard.PasteboardType, Data)]
    }

    private func pasteViaClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // 1. Save all existing pasteboard items & data
        var savedItems: [SavedPasteboardItem] = []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                var itemPairs: [(NSPasteboard.PasteboardType, Data)] = []
                for type in item.types {
                    if let data = item.data(forType: type) {
                        itemPairs.append((type, data))
                    }
                }
                if !itemPairs.isEmpty {
                    savedItems.append(SavedPasteboardItem(typesData: itemPairs))
                }
            }
        }

        // 2. Clear and set new text with transient & concealed markers
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
        let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        pasteboard.setString("VoiceFlow", forType: transientType)
        pasteboard.setString("VoiceFlow", forType: concealedType)

        // 3. Wait 60ms for pasteboard to settle
        usleep(60_000)

        // 4. Simulate Cmd+V via .cgSessionEventTap
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 0x09   // Virtual key for 'v'
        let cmdKeyCode: CGKeyCode = 0x37 // Virtual key for Left Command
        let cmdFlags: CGEventFlags = CGEventFlags(rawValue: 0x00100008) // .maskCommand + NX left-cmd marker

        // Create Command Key events
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: true)
        cmdDown?.flags = cmdFlags

        let vDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        vDown?.flags = cmdFlags

        let vUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        vUp?.flags = cmdFlags

        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cmdKeyCode, keyDown: false)
        cmdUp?.flags = []

        guard let kd = vDown, let ku = vUp else {
            self.logger.error("Failed to create keyboard events for Cmd+V.")
            self.restorePasteboard(savedItems)
            return false
        }

        // Post sequence to .cgSessionEventTap
        cmdDown?.post(tap: .cgSessionEventTap)
        kd.post(tap: .cgSessionEventTap)
        ku.post(tap: .cgSessionEventTap)
        cmdUp?.post(tap: .cgSessionEventTap)

        // 5. Wait 800ms for destination app to consume paste before restoring
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.80) { [weak self] in
            self?.restorePasteboard(savedItems)
        }

        return true
    }

    private func restorePasteboard(_ savedItems: [SavedPasteboardItem]) {
        guard !savedItems.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for savedItem in savedItems {
            let item = NSPasteboardItem()
            for (type, data) in savedItem.typesData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    // MARK: - Secondary: AXUIElement

    private func insertViaAccessibility(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        let copyResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)

        guard copyResult == .success, let focusedElement = focusedElementValue else {
            return false
        }

        let element = focusedElement as! AXUIElement
        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        guard setResult == .success else {
            return false
        }

        // Verify if applied
        var readBackValue: AnyObject?
        let readResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &readBackValue)
        if readResult == .success, let readText = readBackValue as? String, readText == text {
            return true
        }

        return setResult == .success
    }

    // MARK: - Tertiary: CGEvent Unicode Typing

    private func typeViaUnicodeEvents(_ text: String) -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16Chars = Array(text.utf16)

        for charCode in utf16Chars {
            var code = charCode
            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                continue
            }
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &code)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            usleep(2_000) // 2ms between keys
        }
        return true
    }

    // MARK: - Selected Text & Clipboard Capture (Feature 1 & Feature 6)

    public func captureSelectedText() -> String? {
        // Method 1: Accessibility API on focused element (direct, zero clipboard side effects)
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementValue: AnyObject?
        let axResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementValue)
        if axResult == .success, let focusedElement = focusedElementValue {
            var selectedTextValue: AnyObject?
            let textResult = AXUIElementCopyAttributeValue(focusedElement as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedTextValue)
            if textResult == .success, let selectedString = selectedTextValue as? String {
                let trimmed = selectedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    logger.info("Captured selected text via Accessibility API (\(trimmed.count) chars).")
                    return trimmed
                }
            }
        }

        // Method 2: Synthetic Cmd+C snapshot (universal fallback for VS Code, Chrome, Electron)
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount

        let src = CGEventSource(stateID: .combinedSessionState)
        let cKeyCode: CGKeyCode = 8 // 'c'
        let cmdKeyCode: CGKeyCode = 55 // command

        guard let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: true),
              let cDown = CGEvent(keyboardEventSource: src, virtualKey: cKeyCode, keyDown: true),
              let cUp = CGEvent(keyboardEventSource: src, virtualKey: cKeyCode, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: cmdKeyCode, keyDown: false) else {
            return nil
        }

        cDown.flags = .maskCommand
        cUp.flags = .maskCommand

        cmdDown.post(tap: .cghidEventTap)
        cDown.post(tap: .cghidEventTap)
        cUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)

        // Wait up to 50ms for clipboard changeCount to increment
        for _ in 0..<5 {
            usleep(10_000) // 10ms
            if pasteboard.changeCount > initialChangeCount {
                if let copied = pasteboard.string(forType: .string) {
                    let trimmed = copied.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        logger.info("Captured selected text via Cmd+C fallback (\(trimmed.count) chars).")
                        return trimmed
                    }
                }
                break
            }
        }

        return nil
    }

    public func captureClipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func replaceSelectedText(_ newText: String, completion: ((Bool) -> Void)? = nil) {
        // Replaces currently highlighted text in-place using instant clipboard paste
        insertText(newText, completion: completion)
    }
}
