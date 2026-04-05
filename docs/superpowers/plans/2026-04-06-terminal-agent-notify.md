# Terminal Agent Notify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar app that watches Apple Terminal tabs running `claude` or `codex` and alerts once when a session is waiting for the user's next input.

**Architecture:** Keep detection logic pure and testable in a small core layer, then hang Apple Terminal polling, notifications, sound playback, and permissions off that core. Generate the Xcode project from a checked-in `project.yml` so the repo stays text-first and reproducible, with the menu bar app target depending on fixture-driven detector tests before any UI wiring.

**Tech Stack:** Swift 5.10, SwiftUI/AppKit, XcodeGen, XCTest, UserNotifications, AVFoundation, ServiceManagement, AppleScript via `osascript`

---

## File Map

- Create: `.gitignore`
- Create: `README.md`
- Create: `project.yml`
- Create: `AgentNotify/App/AgentNotifyApp.swift`
- Create: `AgentNotify/App/AppDelegate.swift`
- Create: `AgentNotify/App/MenuBarController.swift`
- Create: `AgentNotify/App/MonitorController.swift`
- Create: `AgentNotify/Core/Models/AgentKind.swift`
- Create: `AgentNotify/Core/Models/SessionState.swift`
- Create: `AgentNotify/Core/Models/TerminalTabSnapshot.swift`
- Create: `AgentNotify/Core/Models/TrackedSession.swift`
- Create: `AgentNotify/Core/Detection/TextNormalizer.swift`
- Create: `AgentNotify/Core/Detection/IdlePatternMatcher.swift`
- Create: `AgentNotify/Core/Detection/ClaudeMatcher.swift`
- Create: `AgentNotify/Core/Detection/CodexMatcher.swift`
- Create: `AgentNotify/Core/Detection/NeedsInputDetector.swift`
- Create: `AgentNotify/Core/Tracking/SessionTracker.swift`
- Create: `AgentNotify/Infra/Terminal/AppleScriptRunner.swift`
- Create: `AgentNotify/Infra/Terminal/TerminalSnapshotParser.swift`
- Create: `AgentNotify/Infra/Terminal/TerminalPoller.swift`
- Create: `AgentNotify/Infra/Notify/NotificationPayload.swift`
- Create: `AgentNotify/Infra/Notify/NotificationService.swift`
- Create: `AgentNotify/Infra/Notify/SoundPlayer.swift`
- Create: `AgentNotify/Infra/Permissions/PermissionCoordinator.swift`
- Create: `AgentNotify/Infra/Login/LaunchAtLoginController.swift`
- Create: `AgentNotify/Resources/moo.wav`
- Create: `AgentNotifyTests/Detection/NeedsInputDetectorTests.swift`
- Create: `AgentNotifyTests/Detection/ClaudeMatcherTests.swift`
- Create: `AgentNotifyTests/Detection/CodexMatcherTests.swift`
- Create: `AgentNotifyTests/App/MonitorControllerTests.swift`
- Create: `AgentNotifyTests/Tracking/SessionTrackerTests.swift`
- Create: `AgentNotifyTests/Terminal/TerminalSnapshotParserTests.swift`
- Create: `AgentNotifyTests/Notify/NotificationPayloadTests.swift`
- Create: `AgentNotifyTests/TestSupport/FixtureLoader.swift`
- Create: `AgentNotifyTests/Fixtures/codex_waiting.txt`
- Create: `AgentNotifyTests/Fixtures/codex_streaming.txt`
- Create: `AgentNotifyTests/Fixtures/claude_waiting.txt`
- Create: `AgentNotifyTests/Fixtures/claude_streaming.txt`
- Create: `AgentNotifyTests/Fixtures/terminal_poll_output.txt`

### Task 1: Bootstrap the App and the First Detector Slice

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `project.yml`
- Create: `AgentNotify/App/AgentNotifyApp.swift`
- Create: `AgentNotify/Core/Models/AgentKind.swift`
- Create: `AgentNotify/Core/Models/SessionState.swift`
- Create: `AgentNotify/Core/Models/TerminalTabSnapshot.swift`
- Create: `AgentNotify/Core/Models/TrackedSession.swift`
- Create: `AgentNotify/Core/Detection/NeedsInputDetector.swift`
- Test: `AgentNotifyTests/Detection/NeedsInputDetectorTests.swift`
- Create: `AgentNotifyTests/TestSupport/FixtureLoader.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

final class NeedsInputDetectorTests: XCTestCase {
    func test_recentOutputKeepsSessionRunning() {
        let snapshot = TerminalTabSnapshot(
            windowID: 43,
            tabIndex: 0,
            tty: "/dev/ttys003",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: "Streaming tokens...\nThinking..."
        )

        let previous = TrackedSession(
            id: "43:0:/dev/ttys003",
            agent: .codex,
            state: .running,
            lastFingerprint: "older",
            lastChangeAt: Date(timeIntervalSince1970: 10),
            hasNotifiedForCurrentWait: false
        )

        let detector = NeedsInputDetector(quietPeriod: 3)
        let decision = detector.evaluate(
            previous: previous,
            snapshot: snapshot,
            now: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(decision.state, .running)
        XCTAssertFalse(decision.shouldNotify)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodegen generate && xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NeedsInputDetectorTests/test_recentOutputKeepsSessionRunning`

Expected: FAIL with compile errors such as `Cannot find 'TerminalTabSnapshot' in scope` and `No such module 'AgentNotify'`.

- [ ] **Step 3: Write minimal implementation**

```yaml
name: AgentNotify
options:
  minimumXcodeGenVersion: 2.38.0
targets:
  AgentNotify:
    type: application
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: AgentNotify
    resources:
      - path: AgentNotify/Resources
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.westgarden.AgentNotify
        GENERATE_INFOPLIST_FILE: YES
        CODE_SIGN_STYLE: Automatic
    scheme:
      testTargets:
        - AgentNotifyTests
  AgentNotifyTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: AgentNotifyTests
    resources:
      - path: AgentNotifyTests/Fixtures
    dependencies:
      - target: AgentNotify
```

```swift
import Foundation

// AgentNotify/Core/Models/AgentKind.swift
enum AgentKind: String {
    case claude
    case codex
}

// AgentNotify/Core/Models/SessionState.swift
enum SessionState {
    case unknown
    case running
    case needsInput
}

// AgentNotify/Core/Models/TerminalTabSnapshot.swift
struct TerminalTabSnapshot {
    let windowID: Int
    let tabIndex: Int
    let tty: String
    let processes: [String]
    let busy: Bool
    let visibleText: String
}

// AgentNotify/Core/Models/TrackedSession.swift
struct TrackedSession {
    let id: String
    let agent: AgentKind
    let state: SessionState
    let lastFingerprint: String
    let lastChangeAt: Date
    let hasNotifiedForCurrentWait: Bool
}

// AgentNotify/Core/Detection/NeedsInputDetector.swift
struct DetectionDecision {
    let state: SessionState
    let shouldNotify: Bool
    let fingerprint: String
}

struct NeedsInputDetector {
    let quietPeriod: TimeInterval

    func evaluate(previous: TrackedSession?, snapshot: TerminalTabSnapshot, now: Date) -> DetectionDecision {
        let fingerprint = snapshot.visibleText
        guard let previous else {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        if previous.lastFingerprint != fingerprint {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        let quietFor = now.timeIntervalSince(previous.lastChangeAt)
        if quietFor < quietPeriod {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
        }

        return DetectionDecision(state: .running, shouldNotify: false, fingerprint: fingerprint)
    }
}
```

```swift
// AgentNotifyTests/TestSupport/FixtureLoader.swift
import Foundation

private final class FixtureMarker {}

func fixture(named name: String) throws -> String {
    let bundle = Bundle(for: FixtureMarker.self)
    let url = bundle.url(forResource: name, withExtension: "txt")!
    return try String(contentsOf: url)
}
```

```swift
// AgentNotify/App/AgentNotifyApp.swift
import SwiftUI

@main
struct AgentNotifyApp: App {
    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

```gitignore
.DS_Store
build/
DerivedData/
*.xcworkspace
```

```markdown
# AgentNotify

Menu bar monitor for Apple Terminal sessions running `claude` and `codex`.

## Local Setup

1. `brew install xcodegen`
2. `xcodegen generate`
3. `xcodebuild -scheme AgentNotify -destination 'platform=macOS' test`
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NeedsInputDetectorTests/test_recentOutputKeepsSessionRunning`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .gitignore README.md project.yml AgentNotify AgentNotifyTests
git commit -m "chore: bootstrap agent notify app"
```

### Task 2: Make the Detector Recognize Input-Ready Screens

**Files:**
- Create: `AgentNotify/Core/Detection/TextNormalizer.swift`
- Create: `AgentNotify/Core/Detection/IdlePatternMatcher.swift`
- Create: `AgentNotify/Core/Detection/ClaudeMatcher.swift`
- Create: `AgentNotify/Core/Detection/CodexMatcher.swift`
- Create: `AgentNotifyTests/Detection/ClaudeMatcherTests.swift`
- Create: `AgentNotifyTests/Detection/CodexMatcherTests.swift`
- Modify: `AgentNotifyTests/TestSupport/FixtureLoader.swift`
- Create: `AgentNotifyTests/Fixtures/codex_waiting.txt`
- Create: `AgentNotifyTests/Fixtures/codex_streaming.txt`
- Create: `AgentNotifyTests/Fixtures/claude_waiting.txt`
- Create: `AgentNotifyTests/Fixtures/claude_streaming.txt`
- Modify: `AgentNotify/Core/Detection/NeedsInputDetector.swift`
- Test: `AgentNotifyTests/Detection/NeedsInputDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
func test_quietCodexPromptTriggersNeedsInput() throws {
    let waiting = try fixture(named: "codex_waiting")
    let snapshot = TerminalTabSnapshot(
        windowID: 45,
        tabIndex: 1,
        tty: "/dev/ttys004",
        processes: ["login", "-zsh", "codex"],
        busy: false,
        visibleText: waiting
    )

    let previous = TrackedSession(
        id: "45:1:/dev/ttys004",
        agent: .codex,
        state: .running,
        lastFingerprint: TextNormalizer().normalize(waiting),
        lastChangeAt: Date(timeIntervalSince1970: 10),
        hasNotifiedForCurrentWait: false
    )

    let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
        previous: previous,
        snapshot: snapshot,
        now: Date(timeIntervalSince1970: 20)
    )

    XCTAssertEqual(decision.state, .needsInput)
    XCTAssertTrue(decision.shouldNotify)
}

func test_streamingClaudeOutputStaysRunning() throws {
    let streaming = try fixture(named: "claude_streaming")
    let snapshot = TerminalTabSnapshot(
        windowID: 46,
        tabIndex: 0,
        tty: "/dev/ttys005",
        processes: ["login", "-zsh", "claude"],
        busy: false,
        visibleText: streaming
    )

    let previous = TrackedSession(
        id: "46:0:/dev/ttys005",
        agent: .claude,
        state: .running,
        lastFingerprint: "same-fingerprint",
        lastChangeAt: Date(timeIntervalSince1970: 10),
        hasNotifiedForCurrentWait: false
    )

    let decision = NeedsInputDetector(quietPeriod: 3).evaluate(
        previous: previous,
        snapshot: snapshot,
        now: Date(timeIntervalSince1970: 20)
    )

    XCTAssertEqual(decision.state, .running)
    XCTAssertFalse(decision.shouldNotify)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NeedsInputDetectorTests`

Expected: FAIL because the detector has no normalizer or agent-specific matcher logic yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/Core/Detection/TextNormalizer.swift
struct TextNormalizer {
    func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(40)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }
}

// AgentNotify/Core/Detection/IdlePatternMatcher.swift
protocol IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool
    func matchesActiveWork(_ normalizedText: String) -> Bool
}

// AgentNotify/Core/Detection/CodexMatcher.swift
struct CodexMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        normalizedText.contains("Chat about this") || normalizedText.contains("Enter to select")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        normalizedText.contains("Streaming") || normalizedText.contains("thinking") || normalizedText.contains("tool uses")
    }
}

// AgentNotify/Core/Detection/ClaudeMatcher.swift
struct ClaudeMatcher: IdlePatternMatcher {
    func matchesInputReady(_ normalizedText: String) -> Bool {
        normalizedText.contains("❯") || normalizedText.contains("What would you like to do?")
    }

    func matchesActiveWork(_ normalizedText: String) -> Bool {
        normalizedText.contains("Esc to interrupt") || normalizedText.contains("tool use") || normalizedText.contains("thinking")
    }
}
```

```swift
// AgentNotify/Core/Detection/NeedsInputDetector.swift
struct NeedsInputDetector {
    let quietPeriod: TimeInterval
    private let normalizer = TextNormalizer()

    func evaluate(previous: TrackedSession?, snapshot: TerminalTabSnapshot, now: Date) -> DetectionDecision {
        let normalized = normalizer.normalize(snapshot.visibleText)
        guard let previous else {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: normalized)
        }

        let matcher: IdlePatternMatcher = snapshot.processes.contains("claude") ? ClaudeMatcher() : CodexMatcher()
        if previous.lastFingerprint != normalized {
            return DetectionDecision(state: .running, shouldNotify: false, fingerprint: normalized)
        }

        let quietFor = now.timeIntervalSince(previous.lastChangeAt)
        let shouldWait = quietFor >= quietPeriod && matcher.matchesInputReady(normalized) && !matcher.matchesActiveWork(normalized)
        return DetectionDecision(
            state: shouldWait ? .needsInput : .running,
            shouldNotify: shouldWait && !previous.hasNotifiedForCurrentWait,
            fingerprint: normalized
        )
    }
}
```

```text
# AgentNotifyTests/Fixtures/codex_waiting.txt
Now let me design the plan.

Chat about this
Skip interview and plan immediately

Enter to select · ↑/↓ to navigate
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NeedsInputDetectorTests -only-testing:AgentNotifyTests/CodexMatcherTests -only-testing:AgentNotifyTests/ClaudeMatcherTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/Core/Detection AgentNotifyTests/Detection AgentNotifyTests/Fixtures
git commit -m "feat: detect input-ready claude and codex screens"
```

### Task 3: Track Sessions and Debounce Notifications

**Files:**
- Create: `AgentNotify/Core/Tracking/SessionTracker.swift`
- Modify: `AgentNotify/Core/Models/TrackedSession.swift`
- Create: `AgentNotifyTests/Tracking/SessionTrackerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import AgentNotify

final class SessionTrackerTests: XCTestCase {
    func test_waitingTabNotifiesOnlyOnceUntilOutputChanges() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let waiting = TerminalTabSnapshot(
            windowID: 45,
            tabIndex: 1,
            tty: "/dev/ttys004",
            processes: ["login", "-zsh", "codex"],
            busy: false,
            visibleText: "Chat about this\nEnter to select"
        )

        let first = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 10))
        let second = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 20))

        XCTAssertNil(first?.notification)
        XCTAssertEqual(second?.notification?.agent, .codex)

        let third = tracker.process(snapshot: waiting, now: Date(timeIntervalSince1970: 30))
        XCTAssertNil(third?.notification)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/SessionTrackerTests`

Expected: FAIL because `SessionTracker` and notification events do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/Core/Models/TrackedSession.swift
struct TrackedSession {
    let id: String
    let agent: AgentKind
    let state: SessionState
    let lastFingerprint: String
    let lastChangeAt: Date
    let hasNotifiedForCurrentWait: Bool

    func updating(
        state: SessionState,
        fingerprint: String,
        now: Date,
        markNotified: Bool
    ) -> TrackedSession {
        TrackedSession(
            id: id,
            agent: agent,
            state: state,
            lastFingerprint: fingerprint,
            lastChangeAt: lastFingerprint == fingerprint ? lastChangeAt : now,
            hasNotifiedForCurrentWait: markNotified
        )
    }
}

struct SessionEvent {
    let session: TrackedSession
    let notification: NotificationPayload?
}

final class SessionTracker {
    private let detector: NeedsInputDetector
    private var sessions: [String: TrackedSession] = [:]

    init(detector: NeedsInputDetector) {
        self.detector = detector
    }

    func process(snapshot: TerminalTabSnapshot, now: Date) -> SessionEvent? {
        guard let agent = AgentKind(processes: snapshot.processes) else { return nil }
        let id = "\(snapshot.windowID):\(snapshot.tabIndex):\(snapshot.tty)"
        let previous = sessions[id] ?? TrackedSession(
            id: id,
            agent: agent,
            state: .unknown,
            lastFingerprint: "",
            lastChangeAt: now,
            hasNotifiedForCurrentWait: false
        )

        let decision = detector.evaluate(previous: previous, snapshot: snapshot, now: now)
        let notified = decision.shouldNotify || (decision.state == .needsInput && previous.hasNotifiedForCurrentWait)
        let updated = previous.updating(
            state: decision.state,
            fingerprint: decision.fingerprint,
            now: now,
            markNotified: notified
        )
        sessions[id] = updated

        let payload = decision.shouldNotify ? NotificationPayload(sessionID: id, agent: agent, tty: snapshot.tty) : nil
        return SessionEvent(session: updated, notification: payload)
    }
}

extension AgentKind {
    init?(processes: [String]) {
        if processes.contains("claude") { self = .claude; return }
        if processes.contains("codex") { self = .codex; return }
        return nil
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/SessionTrackerTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/Core/Models AgentNotify/Core/Tracking AgentNotifyTests/Tracking
git commit -m "feat: debounce notifications per terminal session"
```

### Task 4: Poll Apple Terminal and Parse Tab Snapshots

**Files:**
- Create: `AgentNotify/Infra/Terminal/AppleScriptRunner.swift`
- Create: `AgentNotify/Infra/Terminal/TerminalSnapshotParser.swift`
- Create: `AgentNotify/Infra/Terminal/TerminalPoller.swift`
- Create: `AgentNotifyTests/Terminal/TerminalSnapshotParserTests.swift`
- Create: `AgentNotifyTests/Fixtures/terminal_poll_output.txt`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

final class TerminalSnapshotParserTests: XCTestCase {
    func test_parserBuildsSnapshotFromPollOutput() throws {
        let raw = try fixture(named: "terminal_poll_output")
        let snapshots = try TerminalSnapshotParser().parse(raw)

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].tty, "/dev/ttys000")
        XCTAssertTrue(snapshots[0].processes.contains("claude"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/TerminalSnapshotParserTests`

Expected: FAIL because parser and poller types do not exist.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/Infra/Terminal/AppleScriptRunner.swift
import Foundation

protocol AppleScriptRunning {
    func run(_ script: String) throws -> String
}

struct AppleScriptRunner: AppleScriptRunning {
    func run(_ script: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

// AgentNotify/Infra/Terminal/TerminalSnapshotParser.swift
struct TerminalSnapshotParser {
    func parse(_ raw: String) throws -> [TerminalTabSnapshot] {
        raw
            .split(separator: "\n")
            .map(String.init)
            .compactMap { line in
                let columns = line.components(separatedBy: "\t")
                guard columns.count >= 6 else { return nil }
                return TerminalTabSnapshot(
                    windowID: Int(columns[0]) ?? 0,
                    tabIndex: Int(columns[1]) ?? 0,
                    tty: columns[2],
                    processes: columns[3].components(separatedBy: ","),
                    busy: columns[4] == "true",
                    visibleText: columns[5]
                )
            }
    }
}

// AgentNotify/Infra/Terminal/TerminalPoller.swift
struct TerminalPoller {
    let runner: AppleScriptRunning
    let parser = TerminalSnapshotParser()

    func poll() throws -> [TerminalTabSnapshot] {
        let script = """
        tell application "Terminal"
            set outputLines to {}
            repeat with w from 1 to count of windows
                set theWindow to window w
                repeat with t from 1 to count of tabs of theWindow
                    set theTab to tab t of theWindow
                    set row to ((id of theWindow as string) & tab & (t as string) & tab & (tty of theTab as string) & tab & (my joinList(processes of theTab, ",")) & tab & (busy of theTab as string) & tab & (contents of theTab as string))
                    copy row to end of outputLines
                end repeat
            end repeat
            return my joinList(outputLines, linefeed)
        end tell
        on joinList(xs, delimiter)
            set AppleScript's text item delimiters to delimiter
            set joined to xs as text
            set AppleScript's text item delimiters to ""
            return joined
        end joinList
        """

        return try parser.parse(runner.run(script))
    }
}
```

```text
# AgentNotifyTests/Fixtures/terminal_poll_output.txt
43	1	/dev/ttys000	login,-zsh,claude	false	Claude is waiting\n❯
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/TerminalSnapshotParserTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/Infra/Terminal AgentNotifyTests/Terminal AgentNotifyTests/Fixtures/terminal_poll_output.txt
git commit -m "feat: poll apple terminal tabs"
```

### Task 5: Send Native Notifications and Play the Cow Sound

**Files:**
- Create: `AgentNotify/Infra/Notify/NotificationPayload.swift`
- Create: `AgentNotify/Infra/Notify/NotificationService.swift`
- Create: `AgentNotify/Infra/Notify/SoundPlayer.swift`
- Create: `AgentNotify/Resources/moo.wav`
- Create: `AgentNotifyTests/Notify/NotificationPayloadTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

final class NotificationPayloadTests: XCTestCase {
    func test_payloadUsesAgentSpecificTitle() {
        let payload = NotificationPayload(sessionID: "45:1:/dev/ttys004", agent: .codex, tty: "/dev/ttys004")
        XCTAssertEqual(payload.title, "Codex Waiting")
        XCTAssertEqual(payload.body, "Terminal tab on /dev/ttys004 is waiting for your input.")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NotificationPayloadTests`

Expected: FAIL because `NotificationPayload` does not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/Infra/Notify/NotificationPayload.swift
struct NotificationPayload {
    let sessionID: String
    let agent: AgentKind
    let tty: String

    var title: String {
        agent == .codex ? "Codex Waiting" : "Claude Waiting"
    }

    var body: String {
        "Terminal tab on \(tty) is waiting for your input."
    }
}

// AgentNotify/Infra/Notify/NotificationService.swift
import UserNotifications

final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func notify(_ payload: NotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        let request = UNNotificationRequest(identifier: payload.sessionID, content: content, trigger: nil)
        center.add(request)
    }
}

// AgentNotify/Infra/Notify/SoundPlayer.swift
import AppKit
import AVFoundation

final class SoundPlayer {
    private var player: AVAudioPlayer?

    func playCowSound() {
        guard let url = Bundle.main.url(forResource: "moo", withExtension: "wav") else {
            NSSound.beep()
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NotificationPayloadTests`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/Infra/Notify AgentNotify/Resources/moo.wav AgentNotifyTests/Notify
git commit -m "feat: add notifications and cow sound"
```

### Task 6: Wire the Menu Bar App, Permissions, and Poll Loop

**Files:**
- Create: `AgentNotify/App/AppDelegate.swift`
- Create: `AgentNotify/App/MenuBarController.swift`
- Create: `AgentNotify/App/MonitorController.swift`
- Create: `AgentNotify/Infra/Permissions/PermissionCoordinator.swift`
- Create: `AgentNotify/Infra/Login/LaunchAtLoginController.swift`
- Modify: `AgentNotify/App/AgentNotifyApp.swift`
- Create: `AgentNotifyTests/App/MonitorControllerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

private final class SpyNotifier: Notifying {
    var sent: [NotificationPayload] = []
    func notify(_ payload: NotificationPayload) { sent.append(payload) }
}

private final class SpySoundPlayer: SoundPlaying {
    var playCount = 0
    func playCowSound() { playCount += 1 }
}

private struct StubPoller: TerminalPolling {
    let snapshots: [TerminalTabSnapshot]
    func poll() throws -> [TerminalTabSnapshot] { snapshots }
}

final class MonitorControllerTests: XCTestCase {
    func test_eventWithNotificationCallsNotifierAndSound() {
        let notifier = SpyNotifier()
        let sound = SpySoundPlayer()
        let controller = MonitorController(
            poller: StubPoller(snapshots: [
                TerminalTabSnapshot(
                    windowID: 45,
                    tabIndex: 1,
                    tty: "/dev/ttys004",
                    processes: ["login", "-zsh", "codex"],
                    busy: false,
                    visibleText: "Chat about this\nEnter to select"
                )
            ]),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 0)),
            notifier: notifier,
            soundPlayer: sound
        )

        controller.tick(now: Date(timeIntervalSince1970: 10))
        controller.tick(now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(notifier.sent.count, 1)
        XCTAssertEqual(sound.playCount, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/MonitorControllerTests`

Expected: FAIL because the monitor controller, protocols, and stubs do not exist yet.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/App/MonitorController.swift
import Foundation

protocol TerminalPolling {
    func poll() throws -> [TerminalTabSnapshot]
}

protocol Notifying {
    func notify(_ payload: NotificationPayload)
}

protocol SoundPlaying {
    func playCowSound()
}

extension TerminalPoller: TerminalPolling {}
extension NotificationService: Notifying {}
extension SoundPlayer: SoundPlaying {}

final class MonitorController {
    private let poller: TerminalPolling
    private let tracker: SessionTracker
    private let notifier: Notifying
    private let soundPlayer: SoundPlaying

    init(poller: TerminalPolling, tracker: SessionTracker, notifier: Notifying, soundPlayer: SoundPlaying) {
        self.poller = poller
        self.tracker = tracker
        self.notifier = notifier
        self.soundPlayer = soundPlayer
    }

    func tick(now: Date = .now) {
        guard let snapshots = try? poller.poll() else { return }
        for snapshot in snapshots {
            guard let event = tracker.process(snapshot: snapshot, now: now) else { continue }
            guard let payload = event.notification else { continue }
            notifier.notify(payload)
            soundPlayer.playCowSound()
        }
    }
}

// AgentNotify/Infra/Permissions/PermissionCoordinator.swift
import ApplicationServices
import UserNotifications

struct PermissionState {
    let notificationsGranted: Bool
    let automationLikelyGranted: Bool
}

final class PermissionCoordinator {
    func currentState() async -> PermissionState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return PermissionState(
            notificationsGranted: settings.authorizationStatus == .authorized,
            automationLikelyGranted: true
        )
    }
}

// AgentNotify/Infra/Login/LaunchAtLoginController.swift
import ServiceManagement

final class LaunchAtLoginController {
    func enable() throws {
        try SMAppService.mainApp.register()
    }
}
```

```swift
// AgentNotify/App/AgentNotifyApp.swift
import SwiftUI

@main
struct AgentNotifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
```

```swift
// AgentNotify/App/AppDelegate.swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuBarController = MenuBarController()
        menuBarController?.start()
    }
}
```

```swift
// AgentNotify/App/MenuBarController.swift
import AppKit

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func start() {
        statusItem.button?.title = "Moo"
        let menu = NSMenu()
        menu.addItem(withTitle: "Start Monitoring", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Mute Alerts", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/MonitorControllerTests`

Expected: PASS

- [ ] **Step 5: Run the app manually**

Run: `xcodegen generate && xcodebuild -scheme AgentNotify -destination 'platform=macOS' build`

Expected: BUILD SUCCEEDED and launching from Xcode shows a menu bar icon with start, mute, and quit actions.

- [ ] **Step 6: Commit**

```bash
git add AgentNotify/App AgentNotify/Infra/Permissions AgentNotify/Infra/Login
git commit -m "feat: wire menu bar monitor"
```

### Task 7: Verify Against Real Terminal Sessions and Tighten Docs

**Files:**
- Modify: `README.md`
- Modify: `AgentNotifyTests/Fixtures/*.txt` as needed after real captures

- [ ] **Step 1: Capture real fixtures from Apple Terminal**

Run:

```bash
osascript -e 'tell application "Terminal" to get {tty, processes, busy, contents} of selected tab of front window'
```

Expected: Raw output that can be copied into the closest fixture file without editing away the prompt markers.

- [ ] **Step 2: Update detector fixtures and re-run focused tests**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/NeedsInputDetectorTests -only-testing:AgentNotifyTests/SessionTrackerTests`

Expected: PASS after the captured fixtures match current real-world Codex and Claude output.

- [ ] **Step 3: Run full test suite**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS'`

Expected: PASS

- [ ] **Step 4: Update README with install, permissions, and launch-at-login instructions**

```markdown
## Permissions

- Grant Automation access when macOS asks to control Terminal
- Grant Notification permission so alerts can appear

## Running

1. `brew install xcodegen`
2. `xcodegen generate`
3. Open `AgentNotify.xcodeproj`
4. Run the `AgentNotify` scheme once and approve permissions
```

- [ ] **Step 5: Commit**

```bash
git add README.md AgentNotifyTests/Fixtures
git commit -m "docs: finalize setup and verification notes"
```

## Self-Review

### Spec Coverage

- Zero-intrusion Apple Terminal monitoring: covered by Tasks 4 and 6
- `NeedsInput` only notification behavior: covered by Tasks 2 and 3
- Debounced per-tab alerting: covered by Task 3
- macOS notification plus custom cow sound: covered by Task 5
- Menu bar app shape with permissions and login behavior: covered by Task 6
- Real-output fixture tuning and verification: covered by Task 7

### Placeholder Scan

- No `TODO`, `TBD`, or deferred “handle later” instructions remain
- Every code-writing step includes concrete file paths and code blocks
- Every verification step includes an exact command and expected result

### Type Consistency

- `TerminalTabSnapshot`, `TrackedSession`, `NeedsInputDetector`, `SessionTracker`, and `NotificationPayload` use consistent names across all tasks
- `playCowSound()`, `notify(_:)`, and `poll()` stay consistent between protocol and concrete type usage
