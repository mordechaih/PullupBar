import Foundation

protocol KeychainTokenProviding: Sendable {
    func fetchOAuthToken() -> String?
}

struct KeychainTokenProvider: KeychainTokenProviding {
    let runner: ProcessRunning

    init(runner: ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    func fetchOAuthToken() -> String? {
        guard let output = runner.run(
            "/usr/bin/security",
            ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        ) else { return nil }

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { return nil }

        return token
    }
}
