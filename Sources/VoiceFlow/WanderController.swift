import AppKit
import QuartzCore

// MARK: - In-Pill Playground Controller
/// Controls Flow the Bot's playful acrobatics, free roaming, skating, and spinning inside the 126pt pill
public final class WanderController {

    private weak var botView: BotView?

    private var isPlaying = false
    private var stepTimer: Timer?
    private var stepCount = 0

    // Coordinate boundaries inside 126x38 pill (botView width is 28pt)
    public static let minX: CGFloat = 6.0
    public static let maxX: CGFloat = 92.0
    public static let centerX: CGFloat = 49.0

    public init(botView: BotView) {
        self.botView = botView
    }

    deinit {
        stopWandering()
    }

    // MARK: - Start In-Pill Playground

    public func startWandering() {
        guard !isPlaying else { return }
        isPlaying = true
        stepCount = 0

        guard let bot = botView else { return }
        bot.setExpression(.thinking, animated: true)
        bot.startSpinning()

        // 1. First spin right on the left home slot for a moment
        stepTimer = Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
            self?.nextPlaygroundStep()
        }
    }

    public func stopWandering() {
        isPlaying = false
        stepTimer?.invalidate()
        stepTimer = nil
        botView?.stopSpinning()
        botView?.setRotation(degrees: 0.0, animated: true)
        botView?.setBobY(0.0, animated: true)
    }

    // MARK: - Dynamic Playground State Machine

    private func nextPlaygroundStep() {
        guard isPlaying, let bot = botView else { return }

        let currentX = bot.frame.origin.x

        if stepCount == 0 {
            // Step 1: Glide to center while spinning
            stepCount = 1
            bot.startSpinning()
            bot.setLookDirection(CGPoint(x: 0.8, y: 0.0))

            bot.glide(to: Self.centerX, duration: 0.32, timing: CAMediaTimingFunction(name: .easeInEaseOut)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                // Joyful spin in center with floating micro-bob
                bot.setBobY(1.5, animated: true)
                let pause = Double.random(in: 0.22...0.38)
                self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                    bot.setBobY(0.0, animated: true)
                    self?.nextPlaygroundStep()
                }
            }
            return
        }

        if stepCount == 1 {
            // Step 2: Move to the right while spinning
            stepCount = 2
            bot.startSpinning()
            bot.setLookDirection(CGPoint(x: 1.0, y: 0.0))

            bot.glide(to: Self.maxX, duration: 0.30, timing: CAMediaTimingFunction(name: .easeInEaseOut)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                // Spin playfully on the right side
                let pause = Double.random(in: 0.20...0.36)
                self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                    self?.nextPlaygroundStep()
                }
            }
            return
        }

        // StepCount >= 2: Free dynamic roaming & acrobatics inside the pill!
        // Unpredictable, energetic, living companion having fun in its own space
        let actionChoice = Int.random(in: 0...4)

        switch actionChoice {
        case 0:
            // Dynamic skate to a random position across the pill while spinning
            let targetX: CGFloat
            if currentX > Self.centerX {
                targetX = CGFloat.random(in: Self.minX...(Self.centerX - 10.0))
            } else {
                targetX = CGFloat.random(in: (Self.centerX + 10.0)...Self.maxX)
            }
            let distance = abs(targetX - currentX)
            let duration = max(0.24, min(0.48, TimeInterval(distance / 120.0) * 0.55))

            bot.startSpinning()
            bot.setLookDirection(CGPoint(x: targetX > currentX ? 0.9 : -0.9, y: 0.0))

            bot.glide(to: targetX, duration: duration, timing: CAMediaTimingFunction(name: .easeInEaseOut)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                let pause = Double.random(in: 0.12...0.30)
                self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                    self?.nextPlaygroundStep()
                }
            }

        case 1:
            // Fast energetic dash from one extreme to the other
            let targetX = currentX > Self.centerX ? Self.minX : Self.maxX
            bot.startSpinning()
            bot.setLookDirection(CGPoint(x: targetX > currentX ? 1.0 : -1.0, y: 0.0))

            bot.glide(to: targetX, duration: 0.26, timing: CAMediaTimingFunction(controlPoints: 0.25, 1.0, 0.5, 1.0)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                // Little squash bounce upon arrival
                bot.setScale(x: 1.15, y: 0.88, animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
                    bot.setScale(x: 1.0, y: 1.0, animated: true)
                }
                let pause = Double.random(in: 0.14...0.28)
                self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                    self?.nextPlaygroundStep()
                }
            }

        case 2:
            // Dash to center and do an acrobatic head-tilt wiggle
            bot.stopSpinning()
            let tilt = Bool.random() ? 12.0 : -12.0
            bot.setRotation(degrees: tilt, animated: true)
            bot.setLookDirection(CGPoint(x: tilt > 0 ? 0.6 : -0.6, y: 0.4))
            bot.setBobY(1.8, animated: true)

            bot.glide(to: Self.centerX, duration: 0.28, timing: CAMediaTimingFunction(name: .easeOut)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    bot.setRotation(degrees: -tilt * 0.8, animated: true)
                    bot.setBobY(0.0, animated: true)
                }
                let pause = Double.random(in: 0.28...0.45)
                self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                    bot.setRotation(degrees: 0.0, animated: true)
                    self?.nextPlaygroundStep()
                }
            }

        case 3:
            // Continuous fast spin in place with floating bob
            bot.startSpinning()
            bot.setBobY(2.0, animated: true)
            let pause = Double.random(in: 0.30...0.50)
            self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                bot.setBobY(0.0, animated: true)
                self?.nextPlaygroundStep()
            }

        default:
            // Skate to edge and peek out
            let targetX = Bool.random() ? Self.minX : Self.maxX
            bot.startSpinning()
            bot.glide(to: targetX, duration: 0.28, timing: CAMediaTimingFunction(name: .easeInEaseOut)) { [weak self] in
                guard let self = self, self.isPlaying else { return }
                let pause = Double.random(in: 0.15...0.30)
                self.stepTimer = Timer.scheduledTimer(withTimeInterval: pause, repeats: false) { [weak self] _ in
                    self?.nextPlaygroundStep()
                }
            }
        }
    }

    // MARK: - Return to Resting Slot (Success)

    public func returnToPill(completion: @escaping () -> Void) {
        stopWandering()

        guard let bot = botView else {
            completion()
            return
        }

        bot.stopSpinning()
        bot.setLookDirection(.zero)
        bot.setBobY(0.0, animated: true)

        // Smooth glide back to left resting slot (220ms ease-out)
        bot.glide(to: Self.minX, duration: 0.22, timing: CAMediaTimingFunction(name: .easeOut)) { [weak self] in
            // Squish on arrival and smile happily!
            self?.botView?.squish()
            self?.botView?.setExpression(.happy, animated: true)
            completion()
        }
    }

    // MARK: - Alarm Return (Error)

    public func alarmReturn(completion: @escaping () -> Void) {
        stopWandering()

        guard let bot = botView else {
            completion()
            return
        }

        bot.stopSpinning()
        bot.setLookDirection(.zero)
        bot.setExpression(.surprised, animated: true)

        bot.glide(to: Self.minX, duration: 0.18, timing: CAMediaTimingFunction(name: .easeOut)) {
            completion()
        }
    }
}
