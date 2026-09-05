import Foundation
import CoreGraphics
import QuartzCore
import os.log

public enum HotkeyAction {
    case dictate          // Double-tap Control
    case transform        // Double-tap Control with Shift held
}

@MainActor
public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidTriggerAction(_ manager: HotkeyManager, action: HotkeyAction)
}

public final class HotkeyManager: @unchecked Sendable {
    public weak var delegate: HotkeyManagerDelegate?
    private let logger = Config.logger

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Double-Tap Control State
    private var lastControlTapTime: TimeInterval = 0
    private var hadOtherKeyPressed: Bool = false
    public var isRecording: Bool = false
    public static let doubleTapMaxInterval: TimeInterval = 0.38
    public static let doubleTapMinInterval: TimeInterval = 0.05

    public var isEnabled: Bool = true

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard eventTap == nil else { return }

        // Mask for keyDown, keyUp, and flagsChanged (to capture modifier keys like Control)
        let mask = (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            logger.error("Failed to create CGEventTap. Ensure Input Monitoring permission is granted.")
            return
        }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logger.info("HotkeyManager event tap started with Double-Tap Control trigger.")
    }

    public func stop() {
        lastControlTapTime = 0
        hadOtherKeyPressed = false
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
                self.runLoopSource = nil
            }
            self.eventTap = nil
            logger.info("HotkeyManager event tap stopped.")
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.warning("CGEventTap disabled by system (type \(type.rawValue)). Re-enabling.")
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let hasControl = flags.contains(.maskControl)
        let hasCmd = flags.contains(.maskCommand)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // 1. Any regular key press (like C in Ctrl+C, or typing letters) cancels pending double-tap
        if type == .keyDown {
            hadOtherKeyPressed = true
            lastControlTapTime = 0
            return Unmanaged.passUnretained(event)
        }

        // 2. Modifier key changes (Control tapped)
        if type == .flagsChanged {
            let isControlKey = (keyCode == 59 || keyCode == 62) // Left or Right Control key

            if hasControl && isControlKey {
                // If Command or Option is held, this is an IDE/system shortcut (ignore)
                if hasCmd || hasOption {
                    lastControlTapTime = 0
                    return Unmanaged.passUnretained(event)
                }

                // If currently recording: a single tap of Control stops recording immediately!
                if isRecording {
                    isRecording = false
                    lastControlTapTime = 0
                    logger.info("Control tapped while recording -> Stopping session")
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.hotkeyManagerDidTriggerAction(self, action: .dictate)
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Not recording: check for Double-Tap Control
                let now = CACurrentMediaTime()
                let interval = now - lastControlTapTime

                if interval <= Self.doubleTapMaxInterval && interval >= Self.doubleTapMinInterval && !hadOtherKeyPressed {
                    // Double-tap confirmed!
                    lastControlTapTime = 0
                    hadOtherKeyPressed = false

                    let action: HotkeyAction = hasShift ? .transform : .dictate
                    logger.info("Double-Tap Control detected -> Triggering \(String(describing: action))")

                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.hotkeyManagerDidTriggerAction(self, action: action)
                    }
                } else {
                    // First tap
                    lastControlTapTime = now
                    hadOtherKeyPressed = false
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
