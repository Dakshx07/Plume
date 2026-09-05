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

    // Dimensions: 126pt listening pill, capsule height 38pt
    private let pillWidthListening: CGFloat = 126.0
    private let capsuleHeight: CGFloat = 38.0
    private let bottomMargin: CGFloat = 40.0

    public private(set) var pillBotView: BotView!
    public var botView: BotView { return pillBotView }
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

        // Waveform View as primary pill container in window
        waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: pillWidthListening, height: capsuleHeight))
        waveformView.autoresizingMask = [.width, .height]
        window.contentView = waveformView

        // Flow the Bot hosted directly inside the pill! (28x28 inside 38pt pill)
        pillBotView = BotView(frame: NSRect(x: WanderController.minX, y: 5.0, width: 28.0, height: 28.0))
        waveformView.addSubview(pillBotView)

        // Wander Controller orchestrates Flow's dynamic in-pill playground
        wanderController = WanderController(botView: pillBotView)
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

    public func showListening(isTransform: Bool = false) {
        cancelAutoDismiss()
        currentState = .listening
        wanderController.stopWandering()

        guard let window = self.window else { return }

        waveformView.startAnimating()

        let finalFrame = targetFrame(width: pillWidthListening, offsetY: 0)

        // Reset bot to home resting slot
        pillBotView.frame = NSRect(x: WanderController.minX, y: 5.0, width: 28.0, height: 28.0)
        pillBotView.alphaValue = 1.0

        if !isVisibleOnScreen || window.alphaValue < 0.05 {
            isVisibleOnScreen = true
            let initialFrame = targetFrame(width: pillWidthListening, offsetY: -16)
            window.setFrame(initialFrame, display: false)
            window.alphaValue = 0.0
            window.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                window.animator().setFrame(finalFrame, display: true)
                window.animator().alphaValue = 1.0
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(finalFrame, display: true)
                window.animator().alphaValue = 1.0
            }
        }

        if isTransform {
            pillBotView.setExpression(.curious, animated: true)
            pillBotView.setRotation(degrees: -6.0, animated: true)
        } else {
            pillBotView.startListeningGestures()
        }
    }

    public func updateAudioLevel(_ level: Float) {
        if currentState == .listening {
            waveformView.setAudioLevel(level)
            pillBotView.handleVoiceInput(level: level)
        }
    }

    /// When speech ends: Waveform collapses, and Flow the Bot takes the full 126pt pill stage as its playground!
    public func startProcessing() {
        guard currentState == .listening else { return }
        currentState = .processing

        pillBotView.stopListeningGestures()
        waveformView.collapseBars()

        // Launch Flow into dynamic in-pill playground
        wanderController.startWandering()
    }

    /// When transcription and cleanup complete: Flow scurries back to home slot, squishes, and smiles happy eyes!
    public func finishSuccess(completion: (() -> Void)? = nil) {
        currentState = .success
        cancelAutoDismiss()
        pillBotView.stopListeningGestures()

        wanderController.returnToPill { [weak self] in
            completion?()
            // Celebrate for 0.9 second, then smoothly slide out
            self?.autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: false) { [weak self] _ in
                self?.hide()
            }
        }
    }

    public func showError(_ message: String) {
        currentState = .error(message)
        cancelAutoDismiss()
        pillBotView.stopListeningGestures()

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
        pillBotView.stopListeningGestures()
        waveformView.stopAnimating()

        guard let window = self.window, isVisibleOnScreen else { return }
        isVisibleOnScreen = false

        let exitFrame = targetFrame(width: window.frame.width, offsetY: -16)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(exitFrame, display: true)
            window.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.window?.orderOut(nil)
            self.pillBotView.setRotation(degrees: 0.0, animated: false)
            self.pillBotView.setLookDirection(.zero)
        })
    }

    private func cancelAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
    }
}
