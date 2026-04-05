struct ClaudeMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        normalizedText.contains("❯") || normalizedText.contains("What would you like to do?")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        normalizedText.contains("Esc to interrupt") || normalizedText.contains("tool use") || normalizedText.contains("thinking")
    }
}
