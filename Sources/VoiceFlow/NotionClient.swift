import Foundation
import os.log

public enum NotionError: LocalizedError {
    case apiKeyMissing
    case databaseIdMissing
    case invalidResponse
    case badRequest(String)
    case unauthorized
    case databaseNotFound
    case rateLimited
    case serverError(Int, String)
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Notion API key not configured."
        case .databaseIdMissing:
            return "Notion Database ID not configured."
        case .invalidResponse:
            return "Invalid response from Notion API."
        case .badRequest(let message):
            return "Notion error: \(message). Check database properties."
        case .unauthorized:
            return "Notion API key is invalid or unauthorized."
        case .databaseNotFound:
            return "Database not found. Make sure your Notion integration is shared to the database."
        case .rateLimited:
            return "Notion API rate limit exceeded."
        case .serverError(let code, let msg):
            return "Notion error (\(code)): \(msg)"
        case .networkError(let msg):
            return "Network error connecting to Notion: \(msg)"
        }
    }
}

public final class NotionClient {
    public static let shared = NotionClient()
    private let logger = Config.logger

    private init() {}

    public func createPage(title: String, content: String) async throws -> URL? {
        let apiKey = Config.notionAPIKey
        let databaseId = Config.notionDatabaseID

        guard !apiKey.isEmpty else {
            throw NotionError.apiKeyMissing
        }
        guard !databaseId.isEmpty else {
            throw NotionError.databaseIdMissing
        }

        guard let url = URL(string: "https://api.notion.com/v1/pages") else {
            throw NotionError.networkError("Invalid Notion URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 15.0

        // Split paragraphs by double newline
        let rawParagraphs = content.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let paragraphs = rawParagraphs.isEmpty ? [content] : rawParagraphs

        var childrenBlocks: [[String: Any]] = []
        for paragraphText in paragraphs {
            // Notion rich_text limit is 2000 chars per text object
            let truncated = String(paragraphText.prefix(2000))
            let block: [String: Any] = [
                "object": "block",
                "type": "paragraph",
                "paragraph": [
                    "rich_text": [
                        [
                            "type": "text",
                            "text": ["content": truncated]
                        ]
                    ]
                ]
            ]
            childrenBlocks.append(block)
        }

        // Clean database ID (strip dashes if user provided raw or vice versa - Notion accepts UUID format with or without hyphens)
        let cleanDatabaseId = databaseId.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload: [String: Any] = [
            "parent": ["database_id": cleanDatabaseId],
            "properties": [
                "Name": [
                    "title": [
                        [
                            "text": ["content": String(title.prefix(2000))]
                        ]
                    ]
                ]
            ],
            "children": childrenBlocks
        ]

        let httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = httpBody

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotionError.invalidResponse
        }

        let responseJSON = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let message = responseJSON["message"] as? String ?? "Unknown error"

        switch httpResponse.statusCode {
        case 200, 201:
            if let pageURLString = responseJSON["url"] as? String, let pageURL = URL(string: pageURLString) {
                logger.info("Successfully created Notion page.")
                return pageURL
            }
            return nil

        case 400:
            logger.error("Notion 400 Bad Request: \(message)")
            throw NotionError.badRequest(message)

        case 401:
            logger.error("Notion 401 Unauthorized.")
            throw NotionError.unauthorized

        case 404:
            logger.error("Notion 404 Not Found.")
            throw NotionError.databaseNotFound

        case 429:
            logger.warning("Notion 429 Rate limited.")
            throw NotionError.rateLimited

        default:
            logger.error("Notion HTTP \(httpResponse.statusCode): \(message)")
            throw NotionError.serverError(httpResponse.statusCode, message)
        }
    }
}
