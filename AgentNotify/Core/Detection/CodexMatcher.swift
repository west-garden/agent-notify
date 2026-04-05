import Foundation

struct CodexMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        let text = relevantTail(from: normalizedText).lowercased()
        return text.contains("chat about this")
            || text.contains("enter to select")
            || normalizedText.hasPrefix("› ")
            || normalizedText.contains("\n› ")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        let text = relevantTail(from: normalizedText).lowercased()
        return text.contains("streaming") || text.contains("thinking") || text.contains("tool uses")
    }

    private func relevantTail(from normalizedText: String) -> String {
        let lines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard let anchorIndex = lines.lastIndex(where: isInputReadyAnchor) else {
            return normalizedText
        }

        return lines[anchorIndex...].joined(separator: "\n")
    }

    private func isInputReadyAnchor(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        return trimmed.hasPrefix("› ")
            || lowercased.contains("chat about this")
            || lowercased.contains("enter to select")
    }
}
