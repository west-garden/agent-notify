import Foundation

enum OsaLanguage: Equatable {
    case appleScript
    case javaScript

    var arguments: [String] {
        switch self {
        case .appleScript:
            return []
        case .javaScript:
            return ["-l", "JavaScript"]
        }
    }
}

protocol AppleScriptRunning {
    func run(_ script: String, language: OsaLanguage) throws -> String
}

extension AppleScriptRunning {
    func run(_ script: String) throws -> String {
        try run(script, language: .appleScript)
    }
}

enum AppleScriptRunnerError: Error {
    case executionFailed(String)
}

struct AppleScriptRunner: AppleScriptRunning {
    func run(_ script: String, language: OsaLanguage = .appleScript) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = language.arguments + ["-e", script]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppleScriptRunnerError.executionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return output
    }
}
