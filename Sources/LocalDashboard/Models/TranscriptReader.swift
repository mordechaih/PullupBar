import Foundation

struct UsageBlock: Decodable {
    let input_tokens: Int
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
    let output_tokens: Int
}

struct AssistantMessage: Decodable {
    let model: String?
    let usage: UsageBlock?
}

struct TranscriptEntry: Decodable {
    let type: String
    let message: AssistantMessage?
}

struct TranscriptSnapshot: Sendable {
    let model: String
    let contextTokens: Int
    let totalCostUSD: Double
}

func encodedProjectDir(forCwd cwd: String) -> String {
    cwd.replacingOccurrences(of: "/", with: "-")
}

func parseTranscript(atPath path: String) -> TranscriptSnapshot? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    guard let text = String(data: data, encoding: .utf8) else { return nil }

    var latestUsage: UsageBlock?
    var latestModel: String?
    var totalCost = 0.0
    let decoder = JSONDecoder()

    for line in text.split(separator: "\n") {
        guard let lineData = line.data(using: .utf8) else { continue }
        guard let entry = try? decoder.decode(TranscriptEntry.self, from: lineData) else { continue }
        guard entry.type == "assistant", let msg = entry.message, let usage = msg.usage, let model = msg.model else { continue }

        latestUsage = usage
        latestModel = model
        totalCost += cost(for: TokenUsage(
            model: model,
            inputTokens: usage.input_tokens,
            cacheCreationInputTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadInputTokens: usage.cache_read_input_tokens ?? 0,
            outputTokens: usage.output_tokens
        ))
    }

    guard let usage = latestUsage, let model = latestModel else { return nil }
    let contextTokens = usage.input_tokens
        + (usage.cache_creation_input_tokens ?? 0)
        + (usage.cache_read_input_tokens ?? 0)
        + usage.output_tokens

    return TranscriptSnapshot(model: model, contextTokens: contextTokens, totalCostUSD: totalCost)
}
