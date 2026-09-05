import Foundation
import CoreGraphics
import QuartzCore
import os.log

public enum HotkeyAction {
    case dictate          // Option + Space
    case transform        // Shift + Option + Space
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

    public var isEnabled: Bool = true

    public init() {}

    deinit {
        stop()
    }

    public func start() {
        guard eventTap == nil else { return }

        // Mask for keyDown and keyUp
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

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
        logger.info("HotkeyManager event tap started successfully.")
    }

    public func stop() {
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

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let isSpace = (keyCode == Config.Hotkey.spaceKeyCode)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let hasCmd = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)

        // Ignore if Command or Control is held
        guard !hasCmd && !hasControl else {
            return Unmanaged.passUnretained(event)
        }

        let now = CACurrentMediaTime()

        if type == .keyDown {
            if isSpace && hasOption {
                // Immediate keyDown trigger with debounce
                if now - lastToggleTime >= Config.Hotkey.debounceIntervalSeconds {
                    lastToggleTime = now
                    let action: HotkeyAction = hasShift ? .transform : .dictate
                    logger.info("Instant hotkey trigger detected: \(String(describing: action))")

                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.hotkeyManagerDidTriggerAction(self, action: action)
                    }
                }
                // Swallow space keydown
                return nil
            }
        } else if type == .keyUp {
            if isSpace && hasOption {
                // Swallow space keyup
                return nil
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
