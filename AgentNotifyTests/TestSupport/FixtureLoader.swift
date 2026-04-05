import Foundation

private final class FixtureMarker {}

func fixture(named name: String) throws -> String {
    let bundle = Bundle(for: FixtureMarker.self)
    guard let url = bundle.url(forResource: name, withExtension: "txt") else {
        let sourceFixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // TestSupport
            .deletingLastPathComponent() // AgentNotifyTests
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).txt")
        guard FileManager.default.fileExists(atPath: sourceFixtureURL.path) else {
            throw NSError(
                domain: "FixtureLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Missing fixture resource: \(name).txt"]
            )
        }
        return try String(contentsOf: sourceFixtureURL, encoding: .utf8)
    }
    return try String(contentsOf: url, encoding: .utf8)
}
