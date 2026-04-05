struct CodexMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        let text = normalizedText.lowercased()
        return text.contains("chat about this") || text.contains("enter to select")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        let text = normalizedText.lowercased()
        return text.contains("streaming") || text.contains("thinking") || text.contains("tool uses")
    }
}
