import AppKit
import QuartzCore

// MARK: - WanderController
/// Manages Flow the Bot's autonomous wandering behaviors and eye tracking during processing
public final class WanderController {

    private weak var botWindow: BotWindow?
    private weak var overlayWindow: NSWindow?

    private var isWandering = false
    private var currentPattern: WanderPattern = .floatDrift
    private var wanderTimer: Timer?

    public enum WanderPattern: CaseIterable {
        case figureEight
        case curiousPeek
        case bounceIdle
        case circlePatrol
        case floatDrift
    }

    public init(botWindow: BotWindow, overlayWindow: NSWindow) {
        self.botWindow = botWindow
        self.overlayWindow = overlayWindow
    }

    deinit {
        stopWandering()
    }

    // MARK: - Start & Stop

    public func startWandering() {
        guard !isWandering else { return }
        isWandering = true
        botWindow?.botView.setExpression(.curious, animated: true)
        nextWanderStep()
    }

    public func stopWandering() {
        isWandering = false
        wanderTimer?.invalidate()
        wanderTimer = nil
    }

    // MARK: - Wander Loop

    private func nextWanderStep() {
        guard isWandering, let bot = botWindow, let dest = calculateDestination() else { return }

        // Compute movement vector for eye tracking
        let currentOrigin = bot.frame.origin
        let dx = dest.x - currentOrigin.x
        let dy = dest.y - currentOrigin.y
        let distance = sqrt(dx * dx + dy * dy)

        if distance > 1.0 {
            bot.botView.setLookDirection(CGPoint(x: dx / distance, y: dy / distance))
        }

        let duration = TimeInterval.random(in: 1.4...2.4)

        bot.move(to: dest, duration: duration, timing: CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)) { [weak self] in
            guard let self = self, self.isWandering else { return }

            // Pause briefly with curious look, then execute next wander segment
            let pauseDuration = TimeInterval.random(in: 0.35...0.85)
            self.wanderTimer = Timer.scheduledTimer(withTimeInterval: pauseDuration, repeats: false) { [weak self] _ in
                self?.nextWanderStep()
            }
        }
    }

    // MARK: - Pattern Destination Calculation

    private func calculateDestination() -> NSPoint? {
        guard let overlayFrame = overlayWindow?.frame, let bot = botWindow else { return nil }

        let pillCenterX = overlayFrame.origin.x + (overlayFrame.width / 2.0)
        let pillTopY = overlayFrame.origin.y + overlayFrame.height

        currentPattern = WanderPattern.allCases.randomElement() ?? .floatDrift

        switch currentPattern {
        case .figureEight:
            // Alternate left and right loops above the pill
            let offsetX = Bool.random() ? CGFloat.random(in: 35...65) : CGFloat.random(in: -65...(-35))
            let offsetY = CGFloat.random(in: 15...45)
            return NSPoint(x: pillCenterX - (BotWindow.windowSize / 2.0) + offsetX, y: pillTopY + offsetY)

        case .curiousPeek:
            // Drift toward an edge and peer
            let direction = Bool.random() ? CGFloat.random(in: 45...75) : CGFloat.random(in: -75...(-45))
            let height = CGFloat.random(in: 10...35)
            return NSPoint(x: pillCenterX - (BotWindow.windowSize / 2.0) + direction, y: pillTopY + height)

        case .bounceIdle:
            // Small waiting hop
            let currentX = bot.frame.origin.x
            let hopHeight = CGFloat.random(in: 8...20)
            return NSPoint(x: currentX, y: pillTopY + hopHeight)

        case .circlePatrol:
            // Orbiting patrol above the pill
            let angle = CGFloat.random(in: 0.0...(2.0 * .pi))
            let radius: CGFloat = 30.0
            return NSPoint(
                x: pillCenterX - (BotWindow.windowSize / 2.0) + cos(angle) * radius,
                y: pillTopY + 15.0 + sin(angle) * radius
            )

        case .floatDrift:
            // Gentle random drift
            let offsetX = CGFloat.random(in: -50...50)
            let offsetY = CGFloat.random(in: 12...50)
            return NSPoint(x: pillCenterX - (BotWindow.windowSize / 2.0) + offsetX, y: pillTopY + offsetY)
        }
    }

    // MARK: - Return to Pill (Success)

    public func returnToPill(completion: @escaping () -> Void) {
        guard let overlayFrame = overlayWindow?.frame, let bot = botWindow else {
            completion()
            return
        }

        stopWandering()

        let targetX = overlayFrame.origin.x + 8.0 - 4.0
        let targetY = overlayFrame.origin.y + (overlayFrame.height - BotWindow.windowSize) / 2.0

        // 1. Freeze with attentive/wide eyes for 100ms
        bot.botView.setExpression(.attentive, animated: true)
        bot.botView.setLookDirection(CGPoint(x: 0, y: -1.0)) // look down at pill

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            // 2. Dash directly back to the pill slot (380ms ease-in)
            self?.botWindow?.move(
                to: NSPoint(x: targetX, y: targetY),
                duration: 0.38,
                timing: CAMediaTimingFunction(name: .easeIn)
            ) { [weak self] in
                // 3. Squish on arrival and smile happily!
                self?.botWindow?.squish()
                self?.botWindow?.botView.setExpression(.happy, animated: true)
                self?.botWindow?.botView.setLookDirection(.zero)
                completion()
            }
        }
    }

    // MARK: - Alarm Return (Error / Cancel)

    public func alarmReturn(completion: @escaping () -> Void) {
        guard let overlayFrame = overlayWindow?.frame, let bot = botWindow else {
            completion()
            return
        }

        stopWandering()

        let targetX = overlayFrame.origin.x + 8.0 - 4.0
        let targetY = overlayFrame.origin.y + (overlayFrame.height - BotWindow.windowSize) / 2.0

        bot.botView.setExpression(.surprised, animated: true)

        // Fast alarm rush (280ms)
        bot.move(
            to: NSPoint(x: targetX, y: targetY),
            duration: 0.28,
            timing: CAMediaTimingFunction(name: .easeIn)
        ) {
            completion()
        }
    }
}
