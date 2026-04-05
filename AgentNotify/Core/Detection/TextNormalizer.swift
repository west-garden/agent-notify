import Foundation

struct TextNormalizer {
    func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
                with: "",
                options: .regularExpression
            )
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(40)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }
}
