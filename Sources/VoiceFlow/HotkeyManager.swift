import Foundation
import CoreGraphics
import QuartzCore
import os.log

@MainActor
public protocol HotkeyManagerDelegate: AnyObject {
    func hotkeyManagerDidTriggerToggle(_ manager: HotkeyManager)
}

public final class HotkeyManager: @unchecked Sendable {
    public weak var delegate: HotkeyManagerDelegate?
    private let logger = Config.logger

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var keyDownTimestamp: TimeInterval = 0
    private var isTrackingPotentialTap = false
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
        // Handle system disabling the tap due to timeout or user input lag
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

        // Check for Option key (maskAlternate) and Space (code 49)
        let isSpace = (keyCode == Config.Hotkey.spaceKeyCode)
        let hasOption = flags.contains(.maskAlternate)

        let now = CACurrentMediaTime()

        if type == .keyDown {
            if isSpace && hasOption {
                // Potential tap started
                keyDownTimestamp = now
                isTrackingPotentialTap = true
                // Swallow keyDown so space isn't typed
                return nil
            } else {
                // Different key pressed while tracking
                if isTrackingPotentialTap && !isSpace {
                    isTrackingPotentialTap = false
                }
            }
        } else if type == .keyUp {
            if isSpace && isTrackingPotentialTap {
                isTrackingPotentialTap = false
                let tapDuration = now - keyDownTimestamp

                // Within 500ms is considered a tap
                if tapDuration <= Config.Hotkey.maxTapDurationSeconds {
                    // Debounce check (300ms)
                    if now - lastToggleTime >= Config.Hotkey.debounceIntervalSeconds {
                        lastToggleTime = now
                        logger.info("Option+Space hotkey tap detected (duration: \(String(format: "%.2f", tapDuration * 1000))ms).")

                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.hotkeyManagerDidTriggerToggle(self)
                        }
                    }
                    // Swallow keyUp
                    return nil
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }
}
