import Foundation

struct DetectionDecision {
    let state: SessionState
    let shouldNotify: Bool
    let fingerprint: String
    let stabilityFingerprint: String
}

struct StatusFingerprinting {
    private let trailingRegionLineCount = 16
    private let activeContextLineCount = 4

    func statusRegion(from fingerprint: String) -> String {
        let lines = fingerprint
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let anchorIndex = lines.lastIndex(where: isPromptAnchor) else {
            return Array(lines.suffix(trailingRegionLineCount)).joined(separator: "\n")
        }

        let defaultStartIndex = max(0, anchorIndex - activeContextLineCount)
        let statusLeadInIndex = lines[..<anchorIndex].lastIndex(where: isCurrentStatusLeadIn)
        let startIndex = statusLeadInIndex ?? defaultStartIndex
        return lines[startIndex...].joined(separator: "\n")
    }

    func stabilityFingerprint(from statusRegion: String) -> String {
        statusRegion
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .map(stableFingerprintLine)
            .joined(separator: "\n")
    }

    func isPromptAnchor(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        return trimmed.hasPrefix("❯")
            || trimmed.hasPrefix("›")
            || lowercased.contains("what would you like to do?")
            || lowercased.contains("chat about this")
            || lowercased.contains("enter to select")
    }

    private func isCurrentStatusLeadIn(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        return startsWithActivityGlyph(trimmed)
            || lowercased.contains("working (")
            || lowercased.contains("esc to interrupt")
    }

    private func stableFingerprintLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        guard !isPromptAnchor(trimmed) else {
            return trimmed
        }

        var sanitized = trimmed

        if startsWithActivityGlyph(trimmed) {
            sanitized = sanitized.replacingOccurrences(
                of: #"\b\d+h(?: \d+m)?(?: \d+s)?\b|\b\d+m(?: \d+s)?\b|\b\d+s\b"#,
                with: "<DURATION>",
                options: .regularExpression
            )
        }

        if sanitized.contains("⏱️") {
            sanitized = sanitized.replacingOccurrences(
                of: #"⏱️\s*[0-9hms ]+"#,
                with: "⏱️ <DURATION>",
                options: .regularExpression
            )
        }

        if sanitized.lowercased().contains("context") {
            sanitized = sanitized.replacingOccurrences(
                of: #"[█░]+"#,
                with: "<BAR>",
                options: .regularExpression
            )
            sanitized = sanitized.replacingOccurrences(
                of: #"\d+%"#,
                with: "<PERCENT>",
                options: .regularExpression
            )
        }

        if sanitized.contains("tokens") || sanitized.contains("thought for") || sanitized.contains("to interrupt") {
            sanitized = sanitized.replacingOccurrences(
                of: #"\([^)]*\)"#,
                with: "(...)",
                options: .regularExpression
            )
        }

        if sanitized.contains("×") {
            sanitized = sanitized.replacingOccurrences(
                of: #"×\d+"#,
                with: "×#",
                options: .regularExpression
            )
        }

        return sanitized
    }

    private func startsWithActivityGlyph(_ line: String) -> Bool {
        line.hasPrefix("✳ ")
            || line.hasPrefix("· ")
            || line.hasPrefix("✻ ")
            || line.hasPrefix("✶ ")
            || line.hasPrefix("✢ ")
    }
}

struct NeedsInputDetector {
    let quietPeriod: TimeInterval
    private let normalizer = TextNormalizer()
    private let fingerprinting = StatusFingerprinting()

    func evaluate(
        previous: TrackedSession?,
        snapshot: TerminalTabSnapshot,
        now: Date
    ) -> DetectionDecision {
        let fingerprint = normalizer.normalize(snapshot.visibleText)
        let agent = resolvedAgent(previous: previous, snapshot: snapshot)
        let statusRegion = fingerprinting.statusRegion(from: fingerprint)
        let stabilityFingerprint = fingerprinting.stabilityFingerprint(from: statusRegion)

        guard let previous, let agent else {
            return DetectionDecision(
                state: .running,
                shouldNotify: false,
                fingerprint: fingerprint,
                stabilityFingerprint: stabilityFingerprint
            )
        }

        if previous.lastStabilityFingerprint != stabilityFingerprint {
            return DetectionDecision(
                state: .running,
                shouldNotify: false,
                fingerprint: fingerprint,
                stabilityFingerprint: stabilityFingerprint
            )
        }

        let quietFor = now.timeIntervalSince(previous.lastChangeAt)
        let matcher: IdlePatternMatcher = matcher(for: agent)
        let shouldWait = quietFor >= quietPeriod
            && matcher.matchesInputReady(statusRegion)
            && !matcher.matchesActiveWork(statusRegion)
        return DetectionDecision(
            state: shouldWait ? .needsInput : .running,
            shouldNotify: shouldWait && !previous.hasNotifiedForCurrentWait,
            fingerprint: fingerprint,
            stabilityFingerprint: stabilityFingerprint
        )
    }

    private func resolvedAgent(previous: TrackedSession?, snapshot: TerminalTabSnapshot) -> AgentKind? {
        if snapshot.processes.contains("claude") {
            return .claude
        }

        if snapshot.processes.contains("codex") {
            return .codex
        }

        if let previous, !snapshotProcessesClearlyShowPlainShell(snapshot.processes) {
            return previous.agent
        }

        return nil
    }

    private func snapshotProcessesClearlyShowPlainShell(_ processes: [String]) -> Bool {
        guard !processes.isEmpty else {
            return true
        }

        return processes.allSatisfy { isShellProcess($0) }
    }

    private func isShellProcess(_ process: String) -> Bool {
        switch process.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingPrefix("-") {
        case "login", "zsh", "bash", "sh", "fish", "pwsh", "csh", "tcsh", "ksh":
            return true
        default:
            return false
        }
    }

    private func matcher(for agent: AgentKind) -> IdlePatternMatcher {
        switch agent {
        case .claude:
            return ClaudeMatcher()
        case .codex:
            return CodexMatcher()
        }
    }
}

private extension String {
    func trimmingPrefix(_ prefix: Character) -> String {
        guard self.first == prefix else {
            return self
        }
        return String(dropFirst())
    }
}
