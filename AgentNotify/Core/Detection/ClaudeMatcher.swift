struct ClaudeMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        let text = normalizedText.lowercased()
        return normalizedText.contains("❯") || text.contains("what would you like to do?")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        let text = normalizedText.lowercased()
        return text.contains("esc to interrupt") || text.contains("tool use") || text.contains("thinking")
    }
}
