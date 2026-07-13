import Foundation

protocol ProcessRunning: Sendable {
    func run(_ path: String, _ args: [String]) -> String?
    func run(_ path: String, _ args: [String], cwd: String) -> String?
}

extension ProcessRunning {
    func run(_ path: String, _ args: [String], cwd: String) -> String? {
        run(path, args)
    }
}

struct SystemProcessRunner: ProcessRunning {
    func run(_ path: String, _ args: [String]) -> String? {
        runProcess(path, args, cwd: nil)
    }

    func run(_ path: String, _ args: [String], cwd: String) -> String? {
        runProcess(path, args, cwd: cwd)
    }

    private func runProcess(_ path: String, _ args: [String], cwd: String?) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
