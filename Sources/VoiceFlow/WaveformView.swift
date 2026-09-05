import AppKit
import QuartzCore

public final class WaveformView: NSView {
    private let barCount = 7
    private let barWidth: CGFloat = 3.2
    private let barSpacing: CGFloat = 3.8
    private let minBarHeight: CGFloat = 3.5
    private let maxBarHeight: CGFloat = 20.0

    private var levels: [CGFloat]
    private var rawEnergy: CGFloat = 0.0
    private var smoothedEnergy: CGFloat = 0.0

    private var displayTimer: Timer?
    private var phase: CGFloat = 0.0

    public var isCollapsed: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    public override var isFlipped: Bool {
        return false
    }

    public override var isOpaque: Bool {
        return false
    }

    public override init(frame frameRect: NSRect) {
        self.levels = Array(repeating: 3.5, count: 7)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    public required init?(coder: NSCoder) {
        self.levels = Array(repeating: 3.5, count: 7)
        super.init(coder: coder)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    deinit {
        stopAnimating()
    }

    // MARK: - Audio Level Updates

    public func setAudioLevel(_ normalizedLevel: Float) {
        guard !isCollapsed else { return }
        rawEnergy = CGFloat(max(0.0, min(1.0, normalizedLevel)))
    }

    // MARK: - Animation Loop (60fps)

    public func startAnimating() {
        isCollapsed = false
        phase = 0.0
        rawEnergy = 0.0
        smoothedEnergy = 0.0

        for i in 0..<barCount {
            levels[i] = minBarHeight
        }

        guard displayTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.displayTimer = timer
    }

    public func stopAnimating() {
        displayTimer?.invalidate()
        displayTimer = nil
        rawEnergy = 0.0
        smoothedEnergy = 0.0
        needsDisplay = true
    }

    public func collapseBars() {
        isCollapsed = true
        // Smoothly collapse levels to 0
        NSAnimationContext.runAnimationGroup { _ in
            for i in 0..<barCount {
                levels[i] = 0.0
            }
            needsDisplay = true
        }
    }

    private func tick() {
        phase += 0.11
        if phase > .pi * 200.0 {
            phase = 0.0
        }

        if !isCollapsed {
            // Smooth voice energy with fast attack and natural decay
            if rawEnergy > smoothedEnergy {
                smoothedEnergy = smoothedEnergy * 0.35 + rawEnergy * 0.65
            } else {
                smoothedEnergy = smoothedEnergy * 0.88 + rawEnergy * 0.12
            }

            let isSpeaking = smoothedEnergy > 0.04

            for i in 0..<barCount {
                // Multi-harmonic traveling wave equation across the 7 bars
                let w1 = sin(phase * 1.7 + CGFloat(i) * 0.95)
                let w2 = cos(phase * 2.5 - CGFloat(i) * 1.25)
                let w3 = sin(phase * 3.3 + CGFloat(i) * 1.70)
                let waveFactor = (w1 * 0.45 + w2 * 0.35 + w3 * 0.20 + 1.0) / 2.0

                // Center-weighted bias across 7 bars (center is index 3)
                let centerBias: CGFloat = 0.60 + 0.40 * (1.0 - abs(CGFloat(i - 3)) / 3.0)

                let targetHeight: CGFloat
                if isSpeaking {
                    let dynamicHeight = minBarHeight + (maxBarHeight - minBarHeight) * smoothedEnergy * waveFactor * centerBias
                    targetHeight = max(minBarHeight, min(maxBarHeight, dynamicHeight))
                } else {
                    let idleFactor = (sin(phase * 1.2 + CGFloat(i) * 0.80) + 1.0) / 2.0
                    targetHeight = minBarHeight + (idleFactor * 3.0 * centerBias)
                }

                // Asymmetric interpolation: snappy jump up, fluid fall down
                if targetHeight > levels[i] {
                    levels[i] = levels[i] * 0.40 + targetHeight * 0.60
                } else {
                    levels[i] = levels[i] * 0.75 + targetHeight * 0.25
                }
            }
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Wipe transparent background
        context.clear(dirtyRect)

        // 2. Exact pill path
        let pillInsetRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let pillRadius = pillInsetRect.height / 2.0
        let pillPath = CGPath(
            roundedRect: pillInsetRect,
            cornerWidth: pillRadius,
            cornerHeight: pillRadius,
            transform: nil
        )

        // 3. Solid pitch black pill (#0A0A0C)
        context.saveGState()
        context.addPath(pillPath)
        context.setFillColor(NSColor(calibratedRed: 0.04, green: 0.04, blue: 0.05, alpha: 1.0).cgColor)
        context.fillPath()

        // 4. Hairline crisp border (0.75pt, rgba(255,255,255,0.16))
        context.addPath(pillPath)
        context.setStrokeColor(NSColor(white: 1.0, alpha: 0.16).cgColor)
        context.setLineWidth(0.75)
        context.strokePath()

        // 5. Draw wave bars in right section of the pill (left section is for Flow the Bot)
        if !isCollapsed {
            context.addPath(pillPath)
            context.clip()
            drawWaveBars(context: context)
        }

        context.restoreGState()
    }

    private func drawWaveBars(context: CGContext) {
        let totalWaveWidth = (CGFloat(barCount) * barWidth) + (CGFloat(barCount - 1) * barSpacing)
        // Offset start to the right of the bot slot (bot occupies x = 8 to 36)
        let botSectionWidth: CGFloat = 38.0
        let remainingWidth = bounds.width - botSectionWidth
        let startX = botSectionWidth + (remainingWidth - totalWaveWidth) / 2.0
        let centerY = bounds.height / 2.0

        // Crisp solid white bars (#FFFFFF)
        context.setFillColor(NSColor.white.cgColor)

        for i in 0..<barCount {
            let currentX = startX + CGFloat(i) * (barWidth + barSpacing)
            let height = levels[i]
            guard height > 0.5 else { continue }
            let currentY = centerY - (height / 2.0)

            let barRect = CGRect(x: currentX, y: currentY, width: barWidth, height: height)
            let path = CGPath(
                roundedRect: barRect,
                cornerWidth: barWidth / 2.0,
                cornerHeight: barWidth / 2.0,
                transform: nil
            )

            context.addPath(path)
            context.fillPath()
        }
    }
}
