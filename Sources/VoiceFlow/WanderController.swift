import AppKit
import QuartzCore

// MARK: - In-Pill Playground Controller
/// Controls Flow the Bot's playful acrobatics, skating, and spinning inside the 126pt pill during processing
public final class WanderController {

    private weak var botWindow: BotWindow?
    private weak var overlayWindow: NSWindow?

    private var isPlaying = false
    private var stepTimer: Timer?
    private var lastTargetX: CGFloat = 0

    public init(botWindow: BotWindow, overlayWindow: NSWindow) {
        self.botWindow = botWindow
        self.overlayWindow = overlayWindow
    }

    deinit {
        stopWandering()
    }

    // MARK: - Start In-Pill Playground

    public func startWandering() {
        guard !isPlaying else { return }
        isPlaying = true

        guard let bot = botWindow else { return }
        bot.botView.setExpression(.thinking, animated: true)
        bot.botView.startSpinning()

        nextPlaygroundStep()
    }

    public func stopWandering() {
        isPlaying = false
        stepTimer?.invalidate()
        stepTimer = nil
        botWindow?.botView.stopSpinning()
    }

    // MARK: - In-Pill Playground Loop

    private func nextPlaygroundStep() {
        guard isPlaying, let overlayFrame = overlayWindow?.frame, let bot = botWindow else { return }

        // Boundaries strictly inside the 126pt pill:
        // Left slot: overlayFrame.origin.x + 4.0
        // Right slot: overlayFrame.origin.x + overlayFrame.width - BotWindow.windowSize - 4.0 (offset 86pt)
        let minX = overlayFrame.origin.x + 4.0
        let maxX = overlayFrame.origin.x + overlayFrame.width - BotWindow.windowSize - 4.0
        let fixedY = overlayFrame.origin.y + (overlayFrame.height - BotWindow.windowSize) / 2.0

        let currentX = bot.frame.origin.x

        // Alternate across the pill: if currently near left, skate toward right; if near right, skate toward left or center
        let destX: CGFloat
        if abs(currentX - minX) < 15.0 {
            // Skate to the right side of the pill
            destX = CGFloat.random(in: (maxX - 20)...maxX)
        } else if abs(currentX - maxX) < 15.0 {
            // Skate back toward center or left
            destX = CGFloat.random(in: minX...(minX + 30))
        } else {
            // In the middle: pick either extreme
            destX = Bool.random() ? maxX : minX
        }

        let distance = abs(destX - currentX)
        let duration = max(0.40, min(0.85, TimeInterval(distance / 130.0) * 0.70))

        // Set eye direction toward travel direction
        let lookX: CGFloat = destX > currentX ? 1.0 : -1.0
        bot.botView.setLookDirection(CGPoint(x: lookX * 0.8, y: 0.0))

        bot.move(
            to: NSPoint(x: destX, y: fixedY),
            duration: duration,
            timing: CAMediaTimingFunction(name: .easeInEaseOut)
        ) { [weak self] in
            guard let self = self, self.isPlaying else { return }

            // Brief pause to spin in place before next skate
            let pause = Double.random(in: 0.15...0.40)
            self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                self?.nextPlaygroundStep()
            }
        }
    }

    // MARK: - Return to Resting Slot (Success)

    public func returnToPill(completion: @escaping () -> Void) {
        stopWandering()

        guard let overlayFrame = overlayWindow?.frame, let bot = botWindow else {
            completion()
            return
        }

        let targetX = overlayFrame.origin.x + 4.0
        let targetY = overlayFrame.origin.y + (overlayFrame.height - BotWindow.windowSize) / 2.0

        bot.botView.stopSpinning()
        bot.botView.setLookDirection(.zero)

        // Smooth glide back to left slot (240ms ease-out)
        bot.move(
            to: NSPoint(x: targetX, y: targetY),
            duration: 0.24,
            timing: CAMediaTimingFunction(name: .easeOut)
        ) { [weak self] in
            // Squish on arrival and smile happily!
            self?.botWindow?.squish()
            self?.botWindow?.botView.setExpression(.happy, animated: true)
            completion()
        }
    }

    // MARK: - Alarm Return (Error)

    public func alarmReturn(completion: @escaping () -> Void) {
        stopWandering()

        guard let overlayFrame = overlayWindow?.frame, let bot = botWindow else {
            completion()
            return
        }

        let targetX = overlayFrame.origin.x + 4.0
        let targetY = overlayFrame.origin.y + (overlayFrame.height - BotWindow.windowSize) / 2.0

        bot.botView.stopSpinning()
        bot.botView.setExpression(.surprised, animated: true)

        bot.move(
            to: NSPoint(x: targetX, y: targetY),
            duration: 0.20,
            timing: CAMediaTimingFunction(name: .easeOut)
        ) {
            completion()
        }
    }
}
