struct ClaudeMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        let text = normalizedText.lowercased()
        return normalizedText.contains("❯") || text.contains("what would you like to do?")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        let text = normalizedText.lowercased()
        return text.contains("esc to interrupt")
            || text.contains("tool use")
            || text.contains("thinking")
            || hasAnimatedStatusLine(in: normalizedText)
    }

    private func hasAnimatedStatusLine(in normalizedText: String) -> Bool {
        normalizedText
            .split(separator: "\n", omittingEmptySubsequences: false)
            .contains { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("✳ ")
                    || line.hasPrefix("· ")
                    || line.hasPrefix("✻ ")
                    || line.hasPrefix("✶ ")
                    || line.hasPrefix("✢ ")
                else {
                    return false
                }

                return line.contains("…") || line.contains("...")
            }
    }
}
