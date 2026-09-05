import AppKit
import QuartzCore

// MARK: - BotView
/// Custom NSView that renders "Flow" the mascot bot:
/// A clean white circular body with expressive, programmatically modulated black eyes,
/// in-place head rotations/tilts, cadence nodding, and big audio reactions.
public final class BotView: NSView {

    public enum Expression {
        case attentive
        case amazed
        case focused
        case curious
        case happy
        case thinking
        case surprised
        case sleepy
        case proud

        var eyeConfig: EyeConfig {
            switch self {
            case .attentive:
                // Prominent, friendly, large vertical pills (60% larger than original)
                return EyeConfig(width: 4.0, height: 6.4, cornerRadius: 2.0, yOffset: 0, rotation: 0)
            case .amazed:
                // Big reaction: huge, wide open eyes (O O)
                return EyeConfig(width: 5.4, height: 7.6, cornerRadius: 2.7, yOffset: -0.4, rotation: 0)
            case .focused:
                // Alert, engaged listening
                return EyeConfig(width: 3.6, height: 5.4, cornerRadius: 1.8, yOffset: 0, rotation: 0)
            case .curious:
                // Inquisitive, slightly elongated
                return EyeConfig(width: 4.2, height: 6.6, cornerRadius: 2.1, yOffset: -0.6, rotation: 0)
            case .happy:
                // Upward smile arc (⌣ ⌣ shape)
                return EyeConfig(width: 6.4, height: 3.8, cornerRadius: 1.9, yOffset: 0.2, rotation: 0, isArc: true)
            case .thinking:
                return EyeConfig(width: 4.0, height: 6.4, cornerRadius: 2.0, yOffset: 1.2, yOffsetLeft: -1.0, rotation: 0)
            case .surprised:
                // Wide circular eyes on alarm / error
                return EyeConfig(width: 5.8, height: 5.8, cornerRadius: 2.9, yOffset: 0, rotation: 0)
            case .sleepy:
                return EyeConfig(width: 4.0, height: 1.8, cornerRadius: 0.9, yOffset: 0, rotation: 0)
            case .proud:
                return EyeConfig(width: 6.4, height: 3.8, cornerRadius: 1.9, yOffset: 0, rotation: 0, isArc: true)
            }
        }
    }

    public struct EyeConfig {
        var width: CGFloat
        var height: CGFloat
        var cornerRadius: CGFloat
        var yOffset: CGFloat
        var yOffsetLeft: CGFloat
        var rotation: CGFloat
        var isArc: Bool

        init(width: CGFloat, height: CGFloat, cornerRadius: CGFloat, yOffset: CGFloat, yOffsetLeft: CGFloat = 0, rotation: CGFloat = 0, isArc: Bool = false) {
            self.width = width
            self.height = height
            self.cornerRadius = cornerRadius
            self.yOffset = yOffset
            self.yOffsetLeft = yOffsetLeft
            self.rotation = rotation
            self.isArc = isArc
        }
    }

    // MARK: - Properties

    private(set) public var expression: Expression = .attentive

    // Interpolated values for smooth 60fps eye transitions
    private var currentEyeWidth: CGFloat = 4.0
    private var currentEyeHeight: CGFloat = 6.4
    private var currentEyeYOffset: CGFloat = 0
    private var currentLeftEyeYOffset: CGFloat = 0
    private var currentScaleX: CGFloat = 1.0
    private var currentScaleY: CGFloat = 1.0
    private var currentBlink: CGFloat = 1.0 // 1.0 = open, 0.0 = closed

    private var targetEyeWidth: CGFloat = 4.0
    private var targetEyeHeight: CGFloat = 6.4
    private var targetEyeYOffset: CGFloat = 0
    private var targetLeftEyeYOffset: CGFloat = 0
    private var targetScaleX: CGFloat = 1.0
    private var targetScaleY: CGFloat = 1.0

    // In-Place Gestures (Rotation & Bobbing)
    private var currentRotation: CGFloat = 0.0 // in radians
    private var targetRotation: CGFloat = 0.0
    private var currentBobY: CGFloat = 0.0
    private var targetBobY: CGFloat = 0.0
    private var speechPhase: CGFloat = 0.0
    private var isSpinning = false

    // Breathing & eye movement
    private var breathingPhase: CGFloat = 0
    private var lookDirection: CGPoint = .zero // (-1...1, -1...1)

    private var displayTimer: Timer?
    private var blinkTimer: Timer?
    private var gestureTimer: Timer?
    private var amazedHoldTimer: Timer?
    private var isListening = false

    public override var isOpaque: Bool {
        return false
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        displayTimer?.invalidate()
        blinkTimer?.invalidate()
        gestureTimer?.invalidate()
        amazedHoldTimer?.invalidate()
    }

    private func setup() {
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor

        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(displayTimer!, forMode: .common)
        scheduleNextBlink()
    }

    // MARK: - Expressions & Direction

    public func setExpression(_ expr: Expression, animated: Bool = true) {
        expression = expr
        let config = expr.eyeConfig
        if animated {
            targetEyeWidth = config.width
            targetEyeHeight = config.height
            targetEyeYOffset = config.yOffset
            targetLeftEyeYOffset = config.yOffsetLeft
        } else {
            currentEyeWidth = config.width
            currentEyeHeight = config.height
            currentEyeYOffset = config.yOffset
            currentLeftEyeYOffset = config.yOffsetLeft
            targetEyeWidth = config.width
            targetEyeHeight = config.height
            targetEyeYOffset = config.yOffset
            targetLeftEyeYOffset = config.yOffsetLeft
        }
        needsDisplay = true
    }

    public func setLookDirection(_ direction: CGPoint) {
        lookDirection = direction
    }

    public func setScale(x: CGFloat, y: CGFloat, animated: Bool = true) {
        if animated {
            targetScaleX = x
            targetScaleY = y
        } else {
            currentScaleX = x
            currentScaleY = y
            targetScaleX = x
            targetScaleY = y
        }
    }

    public func setRotation(degrees: CGFloat, animated: Bool = true) {
        let radians = degrees * .pi / 180.0
        if animated {
            targetRotation = radians
        } else {
            currentRotation = radians
            targetRotation = radians
        }
    }

    public func setBobY(_ y: CGFloat, animated: Bool = true) {
        if animated {
            targetBobY = y
        } else {
            currentBobY = y
            targetBobY = y
        }
    }

    public func startSpinning() {
        isSpinning = true
    }

    public func stopSpinning() {
        isSpinning = false
        targetRotation = 0.0
    }

    // MARK: - In-Place Gesture Cycle During Listening

    public func startListeningGestures() {
        isListening = true
        // Big welcoming reaction on activate: wide eyes & celebratory little hop!
        setExpression(.amazed, animated: true)
        setBobY(1.5, animated: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) { [weak self] in
            guard let self = self, self.isListening else { return }
            self.setExpression(.attentive, animated: true)
            self.setBobY(0.0, animated: true)
            self.scheduleNextGesture()
        }
    }

    public func stopListeningGestures() {
        isListening = false
        gestureTimer?.invalidate()
        gestureTimer = nil
        amazedHoldTimer?.invalidate()
        amazedHoldTimer = nil
        setRotation(degrees: 0.0, animated: true)
        setBobY(0.0, animated: true)
        setLookDirection(.zero)
    }

    public func handleVoiceInput(level: Float) {
        guard isListening else { return }

        // Speech cadence nod: rhythmic gentle nodding following speech
        if level > 0.08 {
            speechPhase += 0.22
            let nodAmount = sin(speechPhase) * min(CGFloat(level) * 2.2, 1.2)
            targetBobY = nodAmount
        } else {
            targetBobY = targetBobY * 0.85
        }

        // Big reaction on voice crescendo or emphasis (wide eyes O O)
        if level > 0.44 && expression != .amazed && amazedHoldTimer == nil {
            setExpression(.amazed, animated: true)
            setBobY(1.4, animated: true)
            amazedHoldTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
                guard let self = self, self.isListening else { return }
                self.amazedHoldTimer = nil
                self.setExpression(.attentive, animated: true)
                self.setBobY(0.0, animated: true)
            }
        }
    }

    private func scheduleNextGesture() {
        guard isListening else { return }
        let interval = Double.random(in: 1.8...3.0)
        gestureTimer?.invalidate()
        gestureTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.performNextGesture()
        }
    }

    private func performNextGesture() {
        guard isListening else { return }

        let gestureIndex = Int.random(in: 0...4)
        switch gestureIndex {
        case 0:
            // Inquisitive head tilt left (+8 deg) listening intently
            setRotation(degrees: 8.0, animated: true)
            setExpression(.attentive, animated: true)
            setLookDirection(CGPoint(x: -0.2, y: 0.1))
            scheduleGestureReset(after: 1.4)

        case 1:
            // Curious head tilt right (-8 deg) with arched brow
            setRotation(degrees: -8.0, animated: true)
            setExpression(.curious, animated: true)
            setLookDirection(CGPoint(x: 0.2, y: 0.2))
            scheduleGestureReset(after: 1.4)

        case 2:
            // Glance right directly at the jumping waveform bars!
            setRotation(degrees: -2.5, animated: true)
            setExpression(.attentive, animated: true)
            setLookDirection(CGPoint(x: 1.0, y: 0.0))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                guard let self = self, self.isListening else { return }
                self.setLookDirection(.zero)
                self.setRotation(degrees: 0.0, animated: true)
            }
            scheduleNextGesture()

        case 3:
            // Big wide eyes reaction (wonder) with excited little bob
            setRotation(degrees: 0.0, animated: true)
            setExpression(.amazed, animated: true)
            setBobY(1.3, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self, self.isListening else { return }
                self.setExpression(.attentive, animated: true)
                self.setBobY(0.0, animated: true)
            }
            scheduleNextGesture()

        default:
            // Attentive centered pose
            setRotation(degrees: 0.0, animated: true)
            setLookDirection(.zero)
            setExpression(.attentive, animated: true)
            scheduleNextGesture()
        }
    }

    private func scheduleGestureReset(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isListening else { return }
            self.setRotation(degrees: 0.0, animated: true)
            self.setLookDirection(.zero)
            self.scheduleNextGesture()
        }
    }

    // MARK: - Blinking Cycle

    private func scheduleNextBlink() {
        let delay = TimeInterval.random(in: 2.0...4.5)
        blinkTimer?.invalidate()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.performBlink()
        }
    }

    private func performBlink() {
        guard expression != .happy && expression != .proud else {
            scheduleNextBlink()
            return
        }

        let isDoubleBlink = Double.random(in: 0...1) < 0.35
        currentBlink = 0.20
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.currentBlink = 1.0
            if isDoubleBlink {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
                    self?.currentBlink = 0.20
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                        self?.currentBlink = 1.0
                        self?.scheduleNextBlink()
                    }
                }
            } else {
                self?.scheduleNextBlink()
            }
        }
    }

    // MARK: - 60fps Animation Tick

    private func tick() {
        breathingPhase += 0.04
        if breathingPhase > .pi * 200.0 {
            breathingPhase = 0.0
        }

        // Smooth lerp toward target eye geometry
        currentEyeWidth = currentEyeWidth * 0.80 + targetEyeWidth * 0.20
        currentEyeHeight = currentEyeHeight * 0.80 + targetEyeHeight * 0.20
        currentEyeYOffset = currentEyeYOffset * 0.80 + targetEyeYOffset * 0.20
        currentLeftEyeYOffset = currentLeftEyeYOffset * 0.80 + targetLeftEyeYOffset * 0.20
        currentScaleX = currentScaleX * 0.82 + targetScaleX * 0.18
        currentScaleY = currentScaleY * 0.82 + targetScaleY * 0.18

        // Smooth lerp for in-place gestures or continuous spin
        if isSpinning {
            currentRotation += 0.18
            if currentRotation > .pi * 200.0 {
                currentRotation = 0.0
            }
            targetRotation = currentRotation
        } else {
            currentRotation = currentRotation * 0.84 + targetRotation * 0.16
        }
        currentBobY = currentBobY * 0.78 + targetBobY * 0.22

        needsDisplay = true
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Clear transparent buffer
        context.clear(dirtyRect)

        context.saveGState()

        let breathFactor = 1.0 + sin(breathingPhase) * 0.015
        let scaleX = currentScaleX * breathFactor
        let scaleY = currentScaleY * breathFactor

        let center = CGPoint(x: bounds.midX, y: bounds.midY + currentBobY)

        // Rotate in-place around center of the bot body
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: currentRotation)
        context.translateBy(x: -center.x, y: -center.y)

        // Body diameter is 24pt inside a 36pt frame, leaving 6pt margin for shadow
        let baseRadius: CGFloat = 12.0
        let radiusX = baseRadius * scaleX
        let radiusY = baseRadius * scaleY
        let botRect = CGRect(x: center.x - radiusX, y: center.y - radiusY, width: radiusX * 2.0, height: radiusY * 2.0)

        // Subtle soft drop shadow underneath the bot
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1.5),
            blur: 3.5,
            color: NSColor.black.withAlphaComponent(0.25).cgColor
        )
        // Solid pure white body (#FFFFFF)
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: botRect)
        context.restoreGState()

        // Eye positions (centered slightly above middle of the circle)
        let eyeY = center.y + currentEyeYOffset + 1.2
        let eyeSpacing: CGFloat = 4.4
        let eyeOffsetX = lookDirection.x * 1.5
        let eyeOffsetY = -lookDirection.y * 1.2

        let eyeHeightWithBlink = currentEyeHeight * currentBlink

        let leftEyeCenter = CGPoint(x: center.x - eyeSpacing + eyeOffsetX, y: eyeY + currentLeftEyeYOffset + eyeOffsetY)
        let rightEyeCenter = CGPoint(x: center.x + eyeSpacing + eyeOffsetX, y: eyeY + eyeOffsetY)

        let config = expression.eyeConfig
        if config.isArc {
            // Draw upward smile arcs (happy eyes ⌣ ⌣)
            drawHappyEye(at: leftEyeCenter, width: currentEyeWidth, context: context)
            drawHappyEye(at: rightEyeCenter, width: currentEyeWidth, context: context)
        } else {
            // Draw pill-shaped eyes
            drawEye(at: leftEyeCenter, width: currentEyeWidth, height: eyeHeightWithBlink, cornerRadius: config.cornerRadius, context: context)
            drawEye(at: rightEyeCenter, width: currentEyeWidth, height: eyeHeightWithBlink, cornerRadius: config.cornerRadius, context: context)
        }

        context.restoreGState()
    }

    private func drawEye(at center: CGPoint, width: CGFloat, height: CGFloat, cornerRadius: CGFloat, context: CGContext) {
        let safeHeight = max(height, 0.6)
        let eyeRect = CGRect(
            x: center.x - width / 2.0,
            y: center.y - safeHeight / 2.0,
            width: width,
            height: safeHeight
        )
        let safeRadius = min(cornerRadius, min(width, safeHeight) / 2.0)
        context.setFillColor(NSColor.black.cgColor)
        let path = CGPath(
            roundedRect: eyeRect,
            cornerWidth: safeRadius,
            cornerHeight: safeRadius,
            transform: nil
        )
        context.addPath(path)
        context.fillPath()
    }

    private func drawHappyEye(at center: CGPoint, width: CGFloat, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1.8)
        context.setLineCap(.round)

        let halfW = width / 2.0
        let path = CGMutablePath()
        // Smile curve: start left, curve down in center, end right
        path.move(to: CGPoint(x: center.x - halfW, y: center.y + 1.0))
        path.addQuadCurve(
            to: CGPoint(x: center.x + halfW, y: center.y + 1.0),
            control: CGPoint(x: center.x, y: center.y - 2.2)
        )
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }
}

// MARK: - BotWindow
/// Dedicated floating non-activating panel hosting Flow the Bot
public final class BotWindow: NSPanel {

    public let botView: BotView
    public static let windowSize: CGFloat = 36.0

    public init() {
        botView = BotView(frame: NSRect(x: 0, y: 0, width: BotWindow.windowSize, height: BotWindow.windowSize))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: BotWindow.windowSize, height: BotWindow.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false

        contentView = botView
    }

    // MARK: - Positioning

    public func positionInsidePill(_ pillFrame: NSRect) {
        // Position bot at the left inside slot of the pill
        let botX = pillFrame.origin.x + 8.0 - 4.0 // 4pt padding offset for 36pt window over 24pt circle
        let botY = pillFrame.origin.y + (pillFrame.height - BotWindow.windowSize) / 2.0
        setFrameOrigin(NSPoint(x: botX, y: botY))
        orderFrontRegardless()
    }

    // MARK: - Movement Animation

    public func move(to point: NSPoint, duration: TimeInterval, timing: CAMediaTimingFunction? = nil, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = timing ?? CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
            context.allowsImplicitAnimation = true
            self.animator().setFrameOrigin(point)
        }, completionHandler: {
            completion?()
        })
    }

    // MARK: - Physical Reactions

    public func pop() {
        // Spring bounce expansion upon escaping the pill
        botView.setScale(x: 1.22, y: 1.22, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            self?.botView.setScale(x: 1.0, y: 1.0, animated: true)
        }
    }

    public func squish() {
        // Squish on arrival: squash Y, expand X, then spring settle
        botView.setScale(x: 1.25, y: 0.80, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.botView.setScale(x: 0.95, y: 1.05, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
                self?.botView.setScale(x: 1.0, y: 1.0, animated: true)
            }
        }
    }
}
