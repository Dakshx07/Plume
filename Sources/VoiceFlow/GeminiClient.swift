import Foundation
import os.log

public struct NotionNote {
    public let title: String
    public let content: String
}

public enum GeminiFallbackReason {
    case keyNotSet
    case unauthorized
    case rateLimited
    case networkError(String)
    case emptyResponse
    case parseError
}

public final class GeminiClient {
    public static let shared = GeminiClient()
    private let logger = Config.logger

    private init() {}

    // MARK: - Notion Trigger Detection

    private static let notionTriggerPhrases = [
        "save to notion",
        "save this to notion",
        "notion save",
        "add to notion",
        "put this in notion",
        "save to my notion"
    ]

    public func isNotionTrigger(in text: String) -> Bool {
        let lower = text.lowercased()
        return Self.notionTriggerPhrases.contains { lower.contains($0) }
    }

    // MARK: - Process Dictation

    public func cleanDictation(
        rawTranscript: String,
        fallbackNotifier: ((GeminiFallbackReason) -> Void)? = nil
    ) async -> String {
        let key = Config.geminiAPIKey
        guard !key.isEmpty else {
            logger.warning("Gemini API key is not set. Using raw transcript fallback.")
            fallbackNotifier?(.keyNotSet)
            return rawTranscript
        }

        let prompt = """
        You are a speech-to-text post-processor. The user spoke into a voice dictation tool. Convert their speech into clean, properly formatted English text.

        Rules:
        1. If the user spoke in Hinglish (Hindi in English letters), Hindi, or any mix, convert to proper natural English.
        2. Remove filler words (um, uh, like, you know, actually, basically).
        3. Fix grammar and punctuation.
        4. Add proper capitalization.
        5. Do NOT change the meaning. Preserve all information.
        6. Do NOT add commentary, explanations, or notes.
        7. If pure English, just clean it up.
        8. Preserve technical terms exactly (React, Three.js, TypeScript, PostgreSQL, Kubernetes, GSAP, Supabase, Next.js, Vercel, MongoDB, etc.).
        9. Output ONLY the cleaned text, nothing else.

        Examples:
        Input: "mujhe ek React component banana hai jo Three.js use kare"
        Output: I need to build a React component that uses Three.js

        Input: "ye project kal tak complete karna hai"
        Output: This project needs to be completed by tomorrow

        Input: "um so basically I was thinking we could like use Postgres for the database you know"
        Output: I was thinking we could use Postgres for the database

        Now process this speech:
        "\(rawTranscript)"
        """

        do {
            let resultText = try await callGemini(prompt: prompt, apiKey: key)
            let cleaned = stripMarkdownWrappers(resultText)
            if cleaned.isEmpty {
                fallbackNotifier?(.emptyResponse)
                return rawTranscript
            }
            return cleaned
        } catch let error as GeminiError {
            switch error {
            case .unauthorized:
                fallbackNotifier?(.unauthorized)
            case .rateLimited:
                fallbackNotifier?(.rateLimited)
            case .emptyResponse:
                fallbackNotifier?(.emptyResponse)
            case .networkError(let msg):
                fallbackNotifier?(.networkError(msg))
            }
            return rawTranscript
        } catch {
            fallbackNotifier?(.networkError(error.localizedDescription))
            return rawTranscript
        }
    }

    // MARK: - Process for Notion

    public func extractNotionNote(
        rawTranscript: String,
        fallbackNotifier: ((GeminiFallbackReason) -> Void)? = nil
    ) async -> NotionNote {
        let key = Config.geminiAPIKey
        guard !key.isEmpty else {
            fallbackNotifier?(.keyNotSet)
            return NotionNote(
                title: String(rawTranscript.prefix(60)),
                content: rawTranscript
            )
        }

        let prompt = """
        You are a voice-to-Notion assistant. The user spoke and wants to save to Notion. 
        1. Convert any Hinglish/Hindi to proper English.
        2. Clean up speech (remove fillers, fix grammar).
        3. Create a concise title (max 80 chars).
        4. Format body with paragraphs and bullet points if needed.
        5. Do NOT change the meaning. Preserve technical terms.

        Return ONLY a JSON object:
        {"title": "...", "content": "..."}

        No markdown, no code blocks. Just the JSON.

        Speech:
        "\(rawTranscript)"
        """

        do {
            let rawJSON = try await callGemini(prompt: prompt, apiKey: key)
            let stripped = stripMarkdownWrappers(rawJSON)

            if let data = stripped.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let title = obj["title"] as? String,
               let content = obj["content"] as? String {
                return NotionNote(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  content: content.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            // Fallback: parse JSON directly or regex
            let fallbackTitle = String(rawTranscript.prefix(60))
            return NotionNote(title: fallbackTitle, content: stripped.isEmpty ? rawTranscript : stripped)
        } catch {
            return NotionNote(
                title: String(rawTranscript.prefix(60)),
                content: rawTranscript
            )
        }
    }

    // MARK: - Process Transformation (Feature 1 & Feature 6)

    public func transformText(
        contextText: String,
        instruction: String,
        fallbackNotifier: ((GeminiFallbackReason) -> Void)? = nil
    ) async -> String {
        let key = Config.geminiAPIKey
        guard !key.isEmpty else {
            logger.warning("Gemini API key is not set. Using original text fallback.")
            fallbackNotifier?(.keyNotSet)
            return contextText
        }

        let prompt = """
        You are an intelligent in-place text transformation assistant for macOS.
        The user provided the following text and spoke a voice instruction to transform it.

        [Original Text]:
        \"\"\"
        \(contextText)
        \"\"\"

        [User Voice Instruction]:
        \"\"\"
        \(instruction)
        \"\"\"

        Rules:
        1. Execute the user's instruction precisely on the original text (e.g., rewrite, reformat, summarize, translate, fix grammar, convert data formats, write code, etc.).
        2. Output ONLY the transformed text replacement.
        3. Do NOT include any chatty phrases like "Here is the rewritten text:", "Sure!", or explanation notes.
        4. Output only the final replacement text directly.
        """

        do {
            let resultText = try await callGemini(prompt: prompt, apiKey: key)
            let cleaned = stripMarkdownWrappers(resultText)
            if cleaned.isEmpty {
                fallbackNotifier?(.emptyResponse)
                return contextText
            }
            return cleaned
        } catch let error as GeminiError {
            switch error {
            case .unauthorized:
                fallbackNotifier?(.unauthorized)
            case .rateLimited:
                fallbackNotifier?(.rateLimited)
            case .emptyResponse:
                fallbackNotifier?(.emptyResponse)
            case .networkError(let msg):
                fallbackNotifier?(.networkError(msg))
            }
            return contextText
        } catch {
            fallbackNotifier?(.networkError(error.localizedDescription))
            return contextText
        }
    }

    // MARK: - Gemini API Call

    private enum GeminiError: Error {
        case unauthorized
        case rateLimited
        case emptyResponse
        case networkError(String)
    }

    private func callGemini(prompt: String, apiKey: String) async throws -> String {
        let candidateModels = ["gemini-flash-lite-latest", "gemini-2.5-flash-lite", "gemini-flash-latest", "gemini-3.5-flash-lite"]

        for (index, model) in candidateModels.enumerated() {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
                continue
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 15.0

            let payload: [String: Any] = [
                "contents": [
                    [
                        "parts": [
                            ["text": prompt]
                        ]
                    ]
                ],
                "generationConfig": [
                    "temperature": 0.3,
                    "topP": 0.95,
                    "maxOutputTokens": 2048
                ]
            ]

            let httpBody = try JSONSerialization.data(withJSONObject: payload)
            request.httpBody = httpBody

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                if index == candidateModels.count - 1 {
                    throw GeminiError.networkError(error.localizedDescription)
                }
                continue
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                continue
            }

            if httpResponse.statusCode == 404 && index < candidateModels.count - 1 {
                logger.warning("Model \(model) returned 404, trying next candidate.")
                continue
            }

            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logger.error("Gemini API authentication failed (HTTP \(httpResponse.statusCode)).")
                throw GeminiError.unauthorized
            } else if httpResponse.statusCode == 429 {
                logger.warning("Gemini API rate limit exceeded (HTTP 429).")
                throw GeminiError.rateLimited
            } else if httpResponse.statusCode < 200 || httpResponse.statusCode >= 300 {
                logger.error("Gemini API returned status code \(httpResponse.statusCode).")
                throw GeminiError.networkError("HTTP \(httpResponse.statusCode)")
            }

            // Parse candidates[0].content.parts[0].text
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let firstCandidate = candidates.first,
                  let content = firstCandidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let firstPart = parts.first,
                  let text = firstPart["text"] as? String else {
                throw GeminiError.emptyResponse
            }

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw GeminiError.emptyResponse
    }

    private func stripMarkdownWrappers(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code block fences if present (e.g. ```json ... ``` or ``` ... ```)
        if text.hasPrefix("```") {
            let lines = text.components(separatedBy: "\n")
            if lines.count >= 2 {
                let strippedLines = lines.dropFirst().dropLast()
                text = strippedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return text
    }
}
