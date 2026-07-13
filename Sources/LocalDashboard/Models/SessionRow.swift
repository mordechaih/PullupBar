import Foundation

struct SessionRow: Identifiable, Sendable {
    let id: String
    let name: String
    let status: String
    let contextPercent: Int
    let costUSD: Double
}

func computeSessionRows(
    sessionsDir: String,
    projectsDir: String,
    isAlive: (Int) -> Bool = isPidAlive
) -> [SessionRow] {
    let sessions = loadSessions(sessionsDir: sessionsDir, isAlive: isAlive)

    var rows: [SessionRow] = []
    for session in sessions {
        let encodedDir = encodedProjectDir(forCwd: session.cwd)
        let transcriptPath = "\(projectsDir)/\(encodedDir)/\(session.sessionId).jsonl"
        guard let snapshot = parseTranscript(atPath: transcriptPath) else { continue }

        let percent = contextUsedPercent(model: snapshot.model, totalContextTokens: snapshot.contextTokens)
        rows.append(SessionRow(
            id: session.sessionId,
            name: session.name ?? session.sessionId,
            status: session.status,
            contextPercent: percent,
            costUSD: snapshot.totalCostUSD
        ))
    }
    return rows
}
