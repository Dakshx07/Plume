import Foundation
import AVFoundation
import os.log

@MainActor
public protocol AudioRecorderDelegate: AnyObject {
    func audioRecorder(_ recorder: AudioRecorder, didUpdateAudioLevel level: Float, dbLevel: Float)
    func audioRecorderDidDetectSilence(_ recorder: AudioRecorder)
    func audioRecorderDidReachMaxDuration(_ recorder: AudioRecorder)
    func audioRecorder(_ recorder: AudioRecorder, didFailWithError error: Error)
}

public enum AudioRecorderError: LocalizedError {
    case microphoneNotAuthorized
    case engineStartFailed(String)
    case fileCreationFailed(String)
    case deviceDisconnected

    public var errorDescription: String? {
        switch self {
        case .microphoneNotAuthorized:
            return "Microphone permission not granted. Please enable it in System Settings."
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .fileCreationFailed(let reason):
            return "Failed to create audio recording file: \(reason)"
        case .deviceDisconnected:
            return "Audio input device was disconnected."
        }
    }
}

public final class AudioRecorder: NSObject, @unchecked Sendable {
    public weak var delegate: AudioRecorderDelegate?

    private let logger = Config.logger
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?

    private(set) public var isRecording = false
    private(set) public var recordingURL: URL?

    private var recordingStartTime: Date?
    private var silenceStartTime: Date?
    private let processingQueue = DispatchQueue(label: "com.voiceflow.audioprocessing", qos: .userInteractive)

    public override init() {
        super.init()
        setupNotificationObservers()
        prewarm()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopRecording()
    }

    // MARK: - Pre-Warming Engine (Sub-Millisecond Startup)

    public func prewarm() {
        processingQueue.async { [weak self] in
            guard let self = self, self.audioEngine == nil else { return }
            _ = self.getOrInitEngine()
        }
    }

    private func getOrInitEngine() -> AVAudioEngine {
        if let existing = self.audioEngine {
            return existing
        }
        let engine = AVAudioEngine()
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
            logger.info("Voice processing pre-warmed successfully.")
        } catch {
            logger.warning("Voice processing setup note: \(error.localizedDescription)")
        }
        self.audioEngine = engine
        return engine
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleConfigurationChange(_:)),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    @objc private func handleConfigurationChange(_ notification: Notification) {
        processingQueue.async { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.logger.warning("AVAudioEngineConfigurationChange detected mid-recording.")
            self.stopRecording()
            DispatchQueue.main.async {
                self.delegate?.audioRecorder(self, didFailWithError: AudioRecorderError.deviceDisconnected)
            }
        }
    }

    // MARK: - Start Recording

    public func startRecording() throws {
        guard !isRecording else { return }

        // 1. Permission check
        guard Permissions.shared.isMicrophoneGranted else {
            logger.error("Microphone access not granted.")
            throw AudioRecorderError.microphoneNotAuthorized
        }

        let engine = getOrInitEngine()
        let inputNode = engine.inputNode

        // 3. Apple's built-in VAD (macOS 14+)
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            _ = inputNode.setMutedSpeechActivityEventListener { [weak self] event in
                guard let self = self, self.isRecording else { return }
                if event == .ended {
                    // Speech ended according to Apple VAD
                    self.logger.debug("Apple VAD reported speech activity ended.")
                }
            }
        }
        #endif

        // 4. Setup Formats
        let hwFormat = inputNode.inputFormat(forBus: 0)
        let sampleRate = hwFormat.sampleRate > 0 ? hwFormat.sampleRate : 48000.0

        // Install 1-channel mono tap format (AVAudioEngine automatically downmixes spatial/multi-channel mic arrays)
        guard let tapFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw AudioRecorderError.engineStartFailed("Could not create 1-channel tap format.")
        }

        // Target: 16kHz mono linear PCM Int16 for Whisper
        guard let pcmFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Config.Audio.sampleRate,
            channels: Config.Audio.channelCount,
            interleaved: true
        ) else {
            throw AudioRecorderError.engineStartFailed("Could not create target 16kHz mono format.")
        }
        self.targetFormat = pcmFormat

        guard let converter = AVAudioConverter(from: tapFormat, to: pcmFormat) else {
            throw AudioRecorderError.engineStartFailed("Could not create audio converter from \(tapFormat) to \(pcmFormat).")
        }
        self.audioConverter = converter

        // 5. Create temporary WAV file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("voiceflow_\(UUID().uuidString).wav")
        self.recordingURL = fileURL

        let fileSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Config.Audio.sampleRate,
            AVNumberOfChannelsKey: Config.Audio.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        do {
            self.audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: fileSettings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw AudioRecorderError.fileCreationFailed(error.localizedDescription)
        }

        // 6. Install Tap on bus 0 with 1-channel mono format
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
            self?.processIncomingBuffer(buffer)
        }

        // 7. Start Engine
        do {
            try engine.start()
            self.audioEngine = engine
            self.isRecording = true
            self.recordingStartTime = Date()
            self.silenceStartTime = nil
            logger.info("Audio recording started successfully.")
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineStartFailed(error.localizedDescription)
        }
    }

    // MARK: - Buffer Processing

    private func processIncomingBuffer(_ buffer: AVAudioPCMBuffer) {
        processingQueue.async { [weak self] in
            guard let self = self, let audioFile = self.audioFile else { return }

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            // 1. Calculate RMS Energy in dB
            var rms: Float = 0.0
            if let floatData = buffer.floatChannelData {
                let channel = floatData[0]
                var sum: Float = 0.0
                for i in 0..<frameLength {
                    let sample = channel[i]
                    sum += sample * sample
                }
                rms = sqrt(sum / Float(frameLength))
            }

            let db = 20.0 * log10(max(rms, 1e-5))
            // Normalize dB (-60dB...0dB) to 0.0...1.0
            let normalized = max(0.0, min(1.0, (db + 60.0) / 60.0))

            // Notify UI
            DispatchQueue.main.async {
                self.delegate?.audioRecorder(self, didUpdateAudioLevel: normalized, dbLevel: db)
            }

            // 2. Convert and write audio to WAV
            if let converter = self.audioConverter, let targetFormat = self.targetFormat {
                let ratio = targetFormat.sampleRate / buffer.format.sampleRate
                let targetCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 512
                if let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) {
                    var conversionError: NSError?
                    var hasSuppliedBuffer = false

                    let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                        if !hasSuppliedBuffer {
                            hasSuppliedBuffer = true
                            outStatus.pointee = .haveData
                            return buffer
                        } else {
                            outStatus.pointee = .noDataNow
                            return nil
                        }
                    }

                    if status != .error && conversionError == nil && convertedBuffer.frameLength > 0 {
                        do {
                            try audioFile.write(from: convertedBuffer)
                        } catch {
                            self.logger.warning("Error writing audio chunk to file: \(error.localizedDescription)")
                        }
                    }
                }
            }

            // 3. VAD / Silence & Max Duration Detection (active only while isRecording)
            guard self.isRecording, let startTime = self.recordingStartTime else { return }
            let totalDuration = Date().timeIntervalSince(startTime)

            // Safety limit check (120s)
            if totalDuration >= Config.Audio.maxRecordingDurationSeconds {
                self.logger.info("Reached maximum recording duration of \(Config.Audio.maxRecordingDurationSeconds)s.")
                DispatchQueue.main.async {
                    self.delegate?.audioRecorderDidReachMaxDuration(self)
                }
                return
            }

            // Silence check (only active after minRecordingDurationSeconds)
            if totalDuration >= Config.Audio.minRecordingDurationSeconds {
                if db < Config.Audio.silenceThresholdDB {
                    if let silenceStart = self.silenceStartTime {
                        let silenceDuration = Date().timeIntervalSince(silenceStart)
                        if silenceDuration >= Config.Audio.silenceDurationSeconds {
                            self.logger.info("Detected \(silenceDuration)s of silence. Auto-stopping.")
                            self.silenceStartTime = nil
                            DispatchQueue.main.async {
                                self.delegate?.audioRecorderDidDetectSilence(self)
                            }
                        }
                    } else {
                        self.silenceStartTime = Date()
                    }
                } else {
                    self.silenceStartTime = nil
                }
            }
        }
    }

    // MARK: - Stop Recording

    @discardableResult
    public func stopRecording() -> URL? {
        guard isRecording else { return recordingURL }

        isRecording = false
        silenceStartTime = nil
        recordingStartTime = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }

        // Wait synchronously for all queued buffers to finish writing before closing audioFile
        processingQueue.sync {
            self.audioFile = nil // Closes file and writes valid RIFF WAV header with exact audio length
            self.audioConverter = nil
            self.targetFormat = nil
        }

        logger.info("Audio recording stopped and flushed. URL: \(self.recordingURL?.path ?? "nil")")
        return recordingURL
    }

    public func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }
}
