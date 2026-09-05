import AppKit
import QuartzCore

public enum OverlayState: Equatable {
    case listening
    case processing
    case success
    case error(String)
}

public final class OverlayWindowController: NSWindowController {
    public static let shared = OverlayWindowController()

    // Dimensions: 126pt listening pill, shrinks to 56pt resting pebble while bot wanders
    private let pillWidthListening: CGFloat = 126.0
    private let pillWidthProcessing: CGFloat = 56.0
    private let capsuleHeight: CGFloat = 38.0
    private let bottomMargin: CGFloat = 40.0

    public private(set) var botWindow: BotWindow!
    public private(set) var wanderController: WanderController!
    private var waveformView: WaveformView!

    private var autoDismissTimer: Timer?
    private(set) public var currentState: OverlayState = .listening
    private var isVisibleOnScreen = false

    public init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: pillWidthListening, height: capsuleHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true

        super.init(window: panel)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        guard let window = self.window else { return }

        // Waveform View directly in window
        waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: pillWidthListening, height: capsuleHeight))
        waveformView.autoresizingMask = [.width, .height]
        window.contentView = waveformView

        // Initialize Bot Window and Wander Controller
        botWindow = BotWindow()
        wanderController = WanderController(botWindow: botWindow, overlayWindow: window)
    }

    // MARK: - Layout & Positioning (Bottom Center)

    private func targetFrame(width: CGFloat, offsetY: CGFloat = 0) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: width, height: capsuleHeight)
        }

        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - (width / 2.0)
        let y = screenFrame.minY + bottomMargin + offsetY

        return NSRect(x: x, y: y, width: width, height: capsuleHeight)
    }

    // MARK: - Public API

    public func showListening() {
        cancelAutoDismiss()
        currentState = .listening
        wanderController.stopWandering()

        guard let window = self.window else { return }

        waveformView.startAnimating()

        let finalFrame = targetFrame(width: pillWidthListening, offsetY: 0)

        if !isVisibleOnScreen || window.alphaValue < 0.05 {
            isVisibleOnScreen = true
            let initialFrame = targetFrame(width: pillWidthListening, offsetY: -16)
            window.setFrame(initialFrame, display: false)
            window.alphaValue = 0.0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                window.animator().setFrame(finalFrame, display: true)
                window.animator().alphaValue = 1.0
            }

            // Position bot in left slot of pill
            botWindow.positionInsidePill(finalFrame)
            botWindow.botView.startListeningGestures()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(finalFrame, display: true)
                window.animator().alphaValue = 1.0
            }
            botWindow.positionInsidePill(finalFrame)
            botWindow.botView.startListeningGestures()
        }
    }

    public func updateAudioLevel(_ level: Float) {
        if currentState == .listening {
            waveformView.setAudioLevel(level)
            botWindow.botView.handleVoiceInput(level: level)
        }
    }

    /// When speech ends: Waveform collapses, pill shrinks, and Flow the Bot pops out to wander
    public func startProcessing() {
        guard currentState == .listening else { return }
        currentState = .processing

        botWindow.botView.stopListeningGestures()
        waveformView.collapseBars()
        botWindow.pop()

        guard let window = self.window else { return }

        // Smoothly shrink pill to a compact 56pt pebble
        let shrinkFrame = targetFrame(width: pillWidthProcessing, offsetY: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(shrinkFrame, display: true)
        }

        // Launch bot upward out of the pill
        let pillFrame = window.frame
        let escapePoint = NSPoint(
            x: pillFrame.origin.x + (pillFrame.width / 2.0) - (BotWindow.windowSize / 2.0) + CGFloat.random(in: -15...15),
            y: pillFrame.origin.y + pillFrame.height + 22.0
        )

        botWindow.move(to: escapePoint, duration: 0.32, timing: CAMediaTimingFunction(controlPoints: 0.2, 1.0, 0.3, 1.0)) { [weak self] in
            self?.wanderController.startWandering()
        }
    }

    /// When transcription and cleanup complete: Flow the Bot scurries back to the pill, squishes, and smiles happy eyes!
    public func finishSuccess(completion: (() -> Void)? = nil) {
        currentState = .success
        cancelAutoDismiss()
        botWindow.botView.stopListeningGestures()

        guard let window = self.window else {
            completion?()
            return
        }

        // Expand pill back to full width for arrival
        let fullFrame = targetFrame(width: pillWidthListening, offsetY: 0)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(fullFrame, display: true)
        }

        wanderController.returnToPill { [weak self] in
            completion?()
            // Celebrate for 1.2 seconds, then smoothly fade out
            self?.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    public func showError(_ message: String) {
        currentState = .error(message)
        cancelAutoDismiss()
        botWindow.botView.stopListeningGestures()

        guard let window = self.window else { return }

        let fullFrame = targetFrame(width: pillWidthListening, offsetY: 0)
        window.setFrame(fullFrame, display: true)

        wanderController.alarmReturn { [weak self] in
            self?.shakePill()
            self?.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    private func shakePill() {
        guard let layer = waveformView.layer else { return }
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.timingFunction = CAMediaTimingFunction(name: .linear)
        shake.duration = 0.28
        shake.values = [-6, 6, -5, 5, -3, 3, 0]
        layer.add(shake, forKey: "pillShake")
    }

    public func hide() {
        cancelAutoDismiss()
        wanderController.stopWandering()
        botWindow.botView.stopListeningGestures()
        waveformView.stopAnimating()

        guard let window = self.window, isVisibleOnScreen else { return }
        isVisibleOnScreen = false

        let exitFrame = targetFrame(width: window.frame.width, offsetY: -16)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(exitFrame, display: true)
            window.animator().alphaValue = 0.0
            botWindow.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.window?.orderOut(nil)
            self.botWindow.orderOut(nil)
            self.botWindow.alphaValue = 1.0
        })
    }

    private func cancelAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }
}
