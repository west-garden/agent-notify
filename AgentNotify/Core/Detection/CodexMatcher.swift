struct CodexMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        normalizedText.contains("Chat about this") || normalizedText.contains("Enter to select")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        normalizedText.contains("Streaming") || normalizedText.contains("thinking") || normalizedText.contains("tool uses")
    }
}
