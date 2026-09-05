import Foundation
import CoreGraphics
import QuartzCore
import os.log

public enum HotkeyAction {
    case dictate          // Hold Control (~1s)
    case transform        // Hold Shift + Control (~1s)
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
    private var lastToggleTime: TimeInterval = 0

    // Control-Hold State
    private var controlHoldTimer: DispatchWorkItem?
    private var isControlActive: Bool = false
    private var hadOtherKeyPressed: Bool = false
    public var isRecording: Bool = false

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
        logger.info("HotkeyManager event tap started with Control-hold trigger.")
    }

    public func stop() {
        cancelControlHold()
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

    private func cancelControlHold() {
        controlHoldTimer?.cancel()
        controlHoldTimer = nil
        isControlActive = false
        hadOtherKeyPressed = false
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

        // 1. Any regular key press (like C in Ctrl+C, or letters) cancels the hold timer
        if type == .keyDown {
            if isControlActive {
                hadOtherKeyPressed = true
                cancelControlHold()
            }
            return Unmanaged.passUnretained(event)
        }

        // 2. Modifier key changes (Control pressed or released)
        if type == .flagsChanged {
            let isControlKey = (keyCode == 59 || keyCode == 62) // Left or Right Control key

            if hasControl {
                // If Command or Option are held, this is a system shortcut (ignore)
                if hasCmd || hasOption {
                    cancelControlHold()
                    return Unmanaged.passUnretained(event)
                }

                // If currently recording, pressing Control stops recording immediately!
                if isRecording && isControlKey {
                    let now = CACurrentMediaTime()
                    if now - lastToggleTime >= Config.Hotkey.debounceIntervalSeconds {
                        lastToggleTime = now
                        logger.info("Control pressed while recording -> Stopping session")
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.hotkeyManagerDidTriggerAction(self, action: .dictate)
                        }
                    }
                    return Unmanaged.passUnretained(event)
                }

                // Not recording: starting Control hold
                if isControlKey && !isControlActive && !isRecording {
                    isControlActive = true
                    hadOtherKeyPressed = false

                    let action: HotkeyAction = hasShift ? .transform : .dictate

                    // Schedule trigger after holding Control for ~1.1s (1 to <2s)
                    let holdItem = DispatchWorkItem { [weak self] in
                        guard let self = self,
                              self.isControlActive,
                              !self.hadOtherKeyPressed,
                              !self.isRecording else { return }

                        let now = CACurrentMediaTime()
                        self.lastToggleTime = now
                        self.logger.info("Control held for \(Config.Hotkey.controlHoldDurationSeconds)s -> Triggering \(String(describing: action))")

                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.hotkeyManagerDidTriggerAction(self, action: action)
                        }
                    }

                    self.controlHoldTimer = holdItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + Config.Hotkey.controlHoldDurationSeconds, execute: holdItem)
                }
            } else {
                // Control released
                if isControlActive {
                    cancelControlHold()
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
