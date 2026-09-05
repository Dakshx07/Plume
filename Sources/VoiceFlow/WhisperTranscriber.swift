import Foundation
import os.log

public enum WhisperError: LocalizedError {
    case binaryNotFound(String)
    case modelNotFound(String)
    case processFailed(Int32, String)
    case timeout
    case emptyTranscript
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "whisper.cpp not found at \(path)"
        case .modelNotFound(let path):
            return "Whisper model not found at \(path)"
        case .processFailed(let code, let message):
            return "whisper.cpp failed (code \(code)): \(message)"
        case .timeout:
            return "Transcription timed out after 30 seconds."
        case .emptyTranscript:
            return "No speech detected"
        case .fileNotFound(let path):
            return "Audio file not found at \(path)"
        }
    }
}

public final class WhisperTranscriber: @unchecked Sendable {
    private let logger = Config.logger

    public init() {}

    public func transcribe(audioFileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw WhisperError.fileNotFound(audioFileURL.path)
        }

        guard let binaryPath = Config.resolvedWhisperBinaryPath else {
            throw WhisperError.binaryNotFound(Config.preferredWhisperBinaryPath)
        }

        let modelPath = Config.whisperModelPath
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound(modelPath)
        }

        let outputPrefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("whisper_out_\(UUID().uuidString)").path
        let expectedTxtFile = "\(outputPrefix).txt"

        defer {
            try? FileManager.default.removeItem(at: audioFileURL)
            try? FileManager.default.removeItem(atPath: expectedTxtFile)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: binaryPath)

                let isEnglishOnly = modelPath.contains(".en.") || modelPath.hasSuffix(".en.bin")
                process.arguments = [
                    "-m", modelPath,
                    "-f", audioFileURL.path,
                    "-nt",
                    "-of", outputPrefix,
                    "--output-txt",
                    "-l", isEnglishOnly ? "en" : "auto",
                    "-t", "4",
                    "-pp"
                ]

                var env = ProcessInfo.processInfo.environment
                env["GGMETAL"] = "1"
                process.environment = env

                let stderrPipe = Pipe()
                let stdoutPipe = Pipe()
                process.standardError = stderrPipe
                process.standardOutput = stdoutPipe

                var timedOut = false
                let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                timer.schedule(deadline: .now() + 30.0)
                timer.setEventHandler {
                    timedOut = true
                    if process.isRunning {
                        self.logger.error("whisper.cpp timed out after 30s. Terminating.")
                        process.terminate()
                    }
                }
                timer.resume()

                do {
                    try process.run()
                    process.waitUntilExit()
                    timer.cancel()

                    if timedOut {
                        continuation.resume(throwing: WhisperError.timeout)
                        return
                    }

                    let exitCode = process.terminationStatus
                    if exitCode != 0 {
                        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errStr = String(data: errData, encoding: .utf8) ?? "Unknown process error"
                        self.logger.error("whisper.cpp non-zero exit code: \(exitCode)")
                        continuation.resume(throwing: WhisperError.processFailed(exitCode, errStr))
                        return
                    }

                    // Read transcript
                    var rawTranscript = ""
                    if FileManager.default.fileExists(atPath: expectedTxtFile),
                       let fileData = try? Data(contentsOf: URL(fileURLWithPath: expectedTxtFile)),
                       let fileContent = String(data: fileData, encoding: .utf8) {
                        rawTranscript = fileContent
                    } else {
                        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        rawTranscript = String(data: outData, encoding: .utf8) ?? ""
                    }

                    try? stderrPipe.fileHandleForReading.close()
                    try? stdoutPipe.fileHandleForReading.close()
                    try? FileManager.default.removeItem(at: audioFileURL)
                    try? FileManager.default.removeItem(atPath: expectedTxtFile)

                    let cleaned = self.postProcessTranscript(rawTranscript)
                    if cleaned.isEmpty {
                        continuation.resume(throwing: WhisperError.emptyTranscript)
                    } else {
                        continuation.resume(returning: cleaned)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: audioFileURL)
                    try? FileManager.default.removeItem(atPath: expectedTxtFile)
                    timer.cancel()
                    self.logger.error("Failed to run whisper.cpp: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Post-Processing

    private func postProcessTranscript(_ raw: String) -> String {
        var text = raw

        // Remove whisper timestamps: e.g. [00:00:00.000 --> 00:00:05.000] or [00:00:00]
        let timestampPattern = #"\[\d{2}:\d{2}:\d{2}(?:\.\d{3})?(?:\s*-->\s*\d{2}:\d{2}:\d{2}(?:\.\d{3})?)?\]"#
        if let regex = try? NSRegularExpression(pattern: timestampPattern) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: "")
        }

        // Remove hallucination phrases
        let hallucinations = [
            "[BLANK_AUDIO]",
            "[MUSIC]",
            "[SOUND]",
            "Thank you very much.",
            "Thank you very much",
            "Thank you.",
            "Thank you",
            "Please subscribe.",
            "Please subscribe",
            "Thanks for watching!",
            "Thanks for watching.",
            "Thanks for watching",
            "Thank you for watching.",
            "Thank you for watching",
            "Subtitles by",
            "Subscribe to the channel"
        ]

        for h in hallucinations {
            text = text.replacingOccurrences(of: h, with: "", options: .caseInsensitive)
        }

        // Collapse whitespace
        if let wsRegex = try? NSRegularExpression(pattern: #"\s+"#) {
            text = wsRegex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count), withTemplate: " ")
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lone "you" or "you." on silence
        if trimmed.lowercased() == "you" || trimmed.lowercased() == "you." {
            return ""
        }

        return trimmed
    }
}
