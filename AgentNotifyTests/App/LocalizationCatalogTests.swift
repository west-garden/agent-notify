import XCTest

final class LocalizationCatalogTests: XCTestCase {
    func test_quitAgentNotifyButtonHasSimplifiedChineseTranslation() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AgentNotify/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: url)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: Any])
        let quitAgentNotify = try XCTUnwrap(strings["Quit AgentNotify"] as? [String: Any])
        let localizations = try XCTUnwrap(quitAgentNotify["localizations"] as? [String: Any])
        let simplifiedChinese = try XCTUnwrap(localizations["zh-Hans"] as? [String: Any])
        let stringUnit = try XCTUnwrap(simplifiedChinese["stringUnit"] as? [String: Any])
        let value = try XCTUnwrap(stringUnit["value"] as? String)

        XCTAssertEqual(value, "退出 AgentNotify")
    }
}
