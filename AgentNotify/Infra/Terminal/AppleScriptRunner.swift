import Foundation

protocol AppleScriptRunning {
    func run(_ script: String) throws -> String
}

struct AppleScriptRunner: AppleScriptRunning {
    func run(_ script: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
