protocol IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool
    func matchesActiveWork(_ normalizedText: String) -> Bool
}
