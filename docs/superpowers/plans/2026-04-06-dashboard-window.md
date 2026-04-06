# Dashboard Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a click-open dashboard window to the existing menu bar monitor so the user can see waiting tabs, see all tracked tabs, jump directly to `Window X / Tab Y`, and manage mute, login launch, permissions, test sound, and alert cooldown without losing menu bar utility behavior.

**Architecture:** Keep the existing detector and Terminal polling pipeline, but extend it to publish row-level tracked-session state instead of only aggregate counters. Host a SwiftUI dashboard inside one reusable AppKit window, add a small `UserDefaults`-backed settings store for mute and alert cooldown, and route Terminal navigation through a dedicated AppleScript service. Move the actual Terminal poll work off the main thread so opening and using the dashboard stays responsive while the monitor is active.

**Tech Stack:** Swift 5.10, SwiftUI, AppKit, XCTest, UserDefaults, UserNotifications, ServiceManagement, AppleScript via `osascript`

---

## File Map

- Modify: `README.md`
- Modify: `AgentNotify/App/AppDelegate.swift`
- Modify: `AgentNotify/App/MenuBarController.swift`
- Modify: `AgentNotify/App/MonitorController.swift`
- Modify: `AgentNotify/Core/Models/TrackedSession.swift`
- Modify: `AgentNotify/Core/Tracking/SessionTracker.swift`
- Create: `AgentNotify/App/Models/MonitorSnapshot.swift`
- Create: `AgentNotify/App/Dashboard/DashboardViewModel.swift`
- Create: `AgentNotify/App/Dashboard/DashboardView.swift`
- Create: `AgentNotify/App/Dashboard/DashboardWindowController.swift`
- Create: `AgentNotify/Infra/Settings/MonitorSettingsStore.swift`
- Create: `AgentNotify/Infra/Terminal/TerminalNavigator.swift`
- Test: `AgentNotifyTests/Tracking/SessionTrackerTests.swift`
- Test: `AgentNotifyTests/App/MonitorControllerTests.swift`
- Create: `AgentNotifyTests/App/DashboardViewModelTests.swift`
- Create: `AgentNotifyTests/App/MenuBarControllerTests.swift`
- Create: `AgentNotifyTests/Terminal/TerminalNavigatorTests.swift`

### Task 1: Extend Session Tracking for Dashboard Rows

**Files:**
- Modify: `AgentNotify/Core/Models/TrackedSession.swift`
- Modify: `AgentNotify/Core/Tracking/SessionTracker.swift`
- Test: `AgentNotifyTests/Tracking/SessionTrackerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

final class SessionTrackerTests: XCTestCase {
    func test_activeSessionsCarryWindowTabIdentityAndPruneMissingTabs() {
        let tracker = SessionTracker(detector: NeedsInputDetector(quietPeriod: 3))
        let codex = snapshot(
            windowID: 70,
            tabIndex: 1,
            tty: "/dev/ttys020",
            processes: ["login", "-zsh", "codex"],
            visibleText: "› Review this diff\n\ncodex ready"
        )
        let claude = snapshot(
            windowID: 71,
            tabIndex: 3,
            tty: "/dev/ttys021",
            processes: ["login", "-zsh", "claude"],
            visibleText: "Thinking...\nStreaming..."
        )

        _ = tracker.process(snapshot: codex, now: Date(timeIntervalSince1970: 10))
        _ = tracker.process(snapshot: claude, now: Date(timeIntervalSince1970: 10))
        tracker.finishCycle(activeSessionIDs: [
            "70:1:/dev/ttys020",
            "71:3:/dev/ttys021"
        ])

        XCTAssertEqual(
            tracker.activeSessions().map { ($0.windowID, $0.tabIndex, $0.tty) },
            [(70, 1, "/dev/ttys020"), (71, 3, "/dev/ttys021")]
        )

        tracker.finishCycle(activeSessionIDs: ["71:3:/dev/ttys021"])

        XCTAssertEqual(tracker.activeSessions().map(\.id), ["71:3:/dev/ttys021"])
        XCTAssertEqual(tracker.activeSessions().first?.locationLabel, "Window 71 / Tab 3")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/SessionTrackerTests/test_activeSessionsCarryWindowTabIdentityAndPruneMissingTabs`

Expected: FAIL with errors like `Value of type 'SessionTracker' has no member 'finishCycle'`, `Value of type 'SessionTracker' has no member 'activeSessions'`, and `Value of type 'TrackedSession' has no member 'windowID'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/Core/Models/TrackedSession.swift
import Foundation

struct TrackedSession {
    let id: String
    let agent: AgentKind
    let windowID: Int
    let tabIndex: Int
    let tty: String
    let state: SessionState
    let lastFingerprint: String
    let lastChangeAt: Date
    let hasNotifiedForCurrentWait: Bool

    var locationLabel: String {
        "Window \(windowID) / Tab \(tabIndex)"
    }

    func updating(
        snapshot: TerminalTabSnapshot,
        agent: AgentKind? = nil,
        state: SessionState,
        fingerprint: String,
        now: Date,
        markNotified: Bool
    ) -> TrackedSession {
        TrackedSession(
            id: id,
            agent: agent ?? self.agent,
            windowID: snapshot.windowID,
            tabIndex: snapshot.tabIndex,
            tty: snapshot.tty,
            state: state,
            lastFingerprint: fingerprint,
            lastChangeAt: lastFingerprint == fingerprint ? lastChangeAt : now,
            hasNotifiedForCurrentWait: markNotified
        )
    }
}
```

```swift
// AgentNotify/Core/Tracking/SessionTracker.swift
import Foundation

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
        let id = "\(snapshot.windowID):\(snapshot.tabIndex):\(snapshot.tty)"
        let explicitAgent = AgentKind(processes: snapshot.processes)

        if explicitAgent == nil, isPlainShell(snapshot.processes) {
            sessions.removeValue(forKey: id)
            return nil
        }

        guard let effectiveAgent = explicitAgent ?? sessions[id]?.agent else {
            return nil
        }

        let previous = sessions[id] ?? TrackedSession(
            id: id,
            agent: effectiveAgent,
            windowID: snapshot.windowID,
            tabIndex: snapshot.tabIndex,
            tty: snapshot.tty,
            state: .unknown,
            lastFingerprint: "",
            lastChangeAt: now,
            hasNotifiedForCurrentWait: false
        )

        let decision = detector.evaluate(previous: previous, snapshot: snapshot, now: now)
        let notified = decision.shouldNotify || (decision.state == .needsInput && previous.hasNotifiedForCurrentWait)
        let updated = previous.updating(
            snapshot: snapshot,
            agent: explicitAgent,
            state: decision.state,
            fingerprint: decision.fingerprint,
            now: now,
            markNotified: notified
        )

        sessions[id] = updated

        let payload = decision.shouldNotify
            ? NotificationPayload(sessionID: id, agent: effectiveAgent, tty: snapshot.tty)
            : nil

        return SessionEvent(session: updated, notification: payload)
    }

    func finishCycle(activeSessionIDs: Set<String>) {
        sessions = sessions.filter { activeSessionIDs.contains($0.key) }
    }

    func activeSessions() -> [TrackedSession] {
        sessions.values.sorted {
            ($0.windowID, $0.tabIndex, $0.tty) < ($1.windowID, $1.tabIndex, $1.tty)
        }
    }

    private func isPlainShell(_ processes: [String]) -> Bool {
        guard !processes.isEmpty else {
            return true
        }

        return processes.allSatisfy { isShellProcess($0) }
    }

    private func isShellProcess(_ process: String) -> Bool {
        switch process
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingPrefix("-") {
        case "login", "zsh", "bash", "sh", "fish", "pwsh", "csh", "tcsh", "ksh":
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/SessionTrackerTests/test_activeSessionsCarryWindowTabIdentityAndPruneMissingTabs`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/Core/Models/TrackedSession.swift AgentNotify/Core/Tracking/SessionTracker.swift AgentNotifyTests/Tracking/SessionTrackerTests.swift
git commit -m "feat: expose tracked sessions for dashboard rows"
```

### Task 2: Publish Rich Monitor Status and Enforce Alert Cooldown

**Files:**
- Create: `AgentNotify/App/Models/MonitorSnapshot.swift`
- Create: `AgentNotify/Infra/Settings/MonitorSettingsStore.swift`
- Modify: `AgentNotify/App/MonitorController.swift`
- Test: `AgentNotifyTests/App/MonitorControllerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

private final class SequencePoller: TerminalPolling {
    var batches: [[TerminalTabSnapshot]]
    private var index = 0

    func poll() throws -> [TerminalTabSnapshot] {
        defer { index = min(index + 1, batches.count - 1) }
        return batches[index]
    }
}

private final class InMemoryMonitorSettingsStore: MonitorSettingsStoring {
    var isMuted = false
    var alertCooldown: TimeInterval = 60
}

final class MonitorControllerTests: XCTestCase {
    func test_statusIncludesRowsAndSecondAlertWaitsForCooldown() {
        let poller = SequencePoller(batches: [[
            TerminalTabSnapshot(
                windowID: 45,
                tabIndex: 1,
                tty: "/dev/ttys004",
                processes: ["login", "-zsh", "codex"],
                busy: false,
                visibleText: "› first request\n\ncodex ready"
            ),
            TerminalTabSnapshot(
                windowID: 46,
                tabIndex: 2,
                tty: "/dev/ttys005",
                processes: ["login", "-zsh", "claude"],
                busy: false,
                visibleText: "│ waiting for input │"
            )
        ]])

        let notifier = SpyNotifier()
        let sound = SpySoundPlayer()
        let settings = InMemoryMonitorSettingsStore()
        var capturedStatuses: [MonitorStatus] = []

        let controller = MonitorController(
            poller: poller,
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 0)),
            notifier: notifier,
            soundPlayer: sound,
            settingsStore: settings
        )
        controller.onStatusChange = { capturedStatuses.append($0) }

        controller.tick(now: Date(timeIntervalSince1970: 10))
        controller.tick(now: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(notifier.sent.map(\.tty), ["/dev/ttys004"])
        XCTAssertEqual(capturedStatuses.last?.trackedSessionCount, 2)
        XCTAssertEqual(capturedStatuses.last?.waitingSessionCount, 2)
        XCTAssertEqual(capturedStatuses.last?.tabs.filter { $0.isCoolingDown }.count, 1)

        controller.tick(now: Date(timeIntervalSince1970: 90))

        XCTAssertEqual(notifier.sent.map(\.tty), ["/dev/ttys004", "/dev/ttys005"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/MonitorControllerTests/test_statusIncludesRowsAndSecondAlertWaitsForCooldown`

Expected: FAIL with errors like `Cannot find type 'MonitorSettingsStoring' in scope`, `Value of type 'MonitorStatus' has no member 'waitingSessionCount'`, and `Value of type 'MonitorStatus' has no member 'tabs'`.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/App/Models/MonitorSnapshot.swift
import Foundation

struct MonitoredTabState: Equatable, Identifiable {
    let id: String
    let windowID: Int
    let tabIndex: Int
    let agent: AgentKind
    let state: SessionState
    let isCoolingDown: Bool

    var title: String {
        "Window \(windowID) / Tab \(tabIndex)"
    }

    var isWaiting: Bool {
        state == .needsInput
    }
}

struct MonitorStatus {
    let isRunning: Bool
    let isMuted: Bool
    let trackedSessionCount: Int
    let waitingSessionCount: Int
    let tabs: [MonitoredTabState]
    let lastTriggeredTTY: String?
    let lastErrorDescription: String?
}
```

```swift
// AgentNotify/Infra/Settings/MonitorSettingsStore.swift
import Foundation

protocol MonitorSettingsStoring: AnyObject {
    var isMuted: Bool { get set }
    var alertCooldown: TimeInterval { get set }
}

final class MonitorSettingsStore: MonitorSettingsStoring {
    private enum Key {
        static let isMuted = "monitor.isMuted"
        static let alertCooldown = "monitor.alertCooldown"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isMuted: Bool {
        get { defaults.object(forKey: Key.isMuted) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Key.isMuted) }
    }

    var alertCooldown: TimeInterval {
        get {
            let stored = defaults.double(forKey: Key.alertCooldown)
            return stored > 0 ? stored : 60
        }
        set { defaults.set(newValue, forKey: Key.alertCooldown) }
    }
}
```

```swift
// AgentNotify/App/MonitorController.swift
import Foundation

protocol TerminalPolling {
    func poll() throws -> [TerminalTabSnapshot]
}

extension TerminalPoller: TerminalPolling {}

final class MonitorController {
    private let poller: TerminalPolling
    private let tracker: SessionTracker
    private let notifier: Notifying
    private let soundPlayer: SoundPlaying
    private let settingsStore: MonitorSettingsStoring
    private let workerQueue = DispatchQueue(label: "AgentNotify.monitor", qos: .utility)

    private(set) var isRunning = false
    private(set) var isMuted: Bool
    private(set) var trackedSessionCount = 0
    private(set) var waitingSessionCount = 0
    private(set) var tabs: [MonitoredTabState] = []
    private(set) var lastTriggeredTTY: String?
    private(set) var lastErrorDescription: String?

    var onStatusChange: ((MonitorStatus) -> Void)?

    private var timer: Timer?
    private var cooldownUntil: Date?
    private var queuedNotifications: [NotificationPayload] = []

    init(
        poller: TerminalPolling,
        tracker: SessionTracker,
        notifier: Notifying,
        soundPlayer: SoundPlaying,
        settingsStore: MonitorSettingsStoring
    ) {
        self.poller = poller
        self.tracker = tracker
        self.notifier = notifier
        self.soundPlayer = soundPlayer
        self.settingsStore = settingsStore
        self.isMuted = settingsStore.isMuted
    }

    func start(pollInterval: TimeInterval) {
        guard !isRunning else {
            return
        }

        isRunning = true
        publishStatus()

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.workerQueue.async {
                self?.tick()
            }
        }
        timer.tolerance = min(0.5, pollInterval / 4)
        self.timer = timer
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else {
            return
        }

        isMuted = muted
        settingsStore.isMuted = muted
        publishStatus()
    }

    func setAlertCooldown(_ cooldown: TimeInterval) {
        settingsStore.alertCooldown = cooldown
    }

    func playTestSound() {
        soundPlayer.playCowSound()
    }

    func tick(now: Date = .now) {
        do {
            let snapshots = try poller.poll()
            var activeIDs = Set<String>()
            var candidatePayloads: [NotificationPayload] = []

            for snapshot in snapshots {
                let id = "\(snapshot.windowID):\(snapshot.tabIndex):\(snapshot.tty)"
                activeIDs.insert(id)

                guard let event = tracker.process(snapshot: snapshot, now: now) else {
                    continue
                }

                if let payload = event.notification {
                    candidatePayloads.append(payload)
                }
            }

            tracker.finishCycle(activeSessionIDs: activeIDs)
            flushNotifications(candidatePayloads, now: now)

            let sessions = tracker.activeSessions()
            tabs = sessions.map { session in
                MonitoredTabState(
                    id: session.id,
                    windowID: session.windowID,
                    tabIndex: session.tabIndex,
                    agent: session.agent,
                    state: session.state,
                    isCoolingDown: queuedNotifications.contains { $0.sessionID == session.id }
                )
            }
            trackedSessionCount = tabs.count
            waitingSessionCount = tabs.filter(\.isWaiting).count
            lastErrorDescription = nil
        } catch {
            trackedSessionCount = 0
            waitingSessionCount = 0
            tabs = []
            lastErrorDescription = error.localizedDescription
        }

        publishStatus()
    }

    private func flushNotifications(_ candidatePayloads: [NotificationPayload], now: Date) {
        if let cooldownUntil, now < cooldownUntil {
            queuedNotifications.append(contentsOf: candidatePayloads)
            return
        }

        let nextPayload = queuedNotifications.first ?? candidatePayloads.first
        if queuedNotifications.isEmpty {
            queuedNotifications = Array(candidatePayloads.dropFirst())
        } else {
            queuedNotifications = Array(queuedNotifications.dropFirst()) + candidatePayloads
        }

        guard let nextPayload else {
            return
        }

        lastTriggeredTTY = nextPayload.tty
        cooldownUntil = now.addingTimeInterval(settingsStore.alertCooldown)

        guard !isMuted else {
            return
        }

        notifier.notify(nextPayload)
        soundPlayer.playCowSound()
    }

    private func publishStatus() {
        let status = MonitorStatus(
            isRunning: isRunning,
            isMuted: isMuted,
            trackedSessionCount: trackedSessionCount,
            waitingSessionCount: waitingSessionCount,
            tabs: tabs,
            lastTriggeredTTY: lastTriggeredTTY,
            lastErrorDescription: lastErrorDescription
        )

        if Thread.isMainThread {
            onStatusChange?(status)
        } else {
            DispatchQueue.main.async { [onStatusChange] in
                onStatusChange?(status)
            }
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/MonitorControllerTests/test_statusIncludesRowsAndSecondAlertWaitsForCooldown`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/App/Models/MonitorSnapshot.swift AgentNotify/App/MonitorController.swift AgentNotify/Infra/Settings/MonitorSettingsStore.swift AgentNotifyTests/App/MonitorControllerTests.swift
git commit -m "feat: publish dashboard-ready monitor state"
```

### Task 3: Build the Dashboard View Model and Reusable Window

**Files:**
- Create: `AgentNotify/App/Dashboard/DashboardViewModel.swift`
- Create: `AgentNotify/App/Dashboard/DashboardView.swift`
- Create: `AgentNotify/App/Dashboard/DashboardWindowController.swift`
- Create: `AgentNotifyTests/App/DashboardViewModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

final class DashboardViewModelTests: XCTestCase {
    func test_applyBuildsAlertFirstSectionsAndEmptyState() {
        let viewModel = DashboardViewModel()

        viewModel.apply(
            status: MonitorStatus(
                isRunning: true,
                isMuted: false,
                trackedSessionCount: 2,
                waitingSessionCount: 1,
                tabs: [
                    MonitoredTabState(
                        id: "1",
                        windowID: 1,
                        tabIndex: 1,
                        agent: .codex,
                        state: .running,
                        isCoolingDown: false
                    ),
                    MonitoredTabState(
                        id: "2",
                        windowID: 2,
                        tabIndex: 3,
                        agent: .claude,
                        state: .needsInput,
                        isCoolingDown: false
                    )
                ],
                lastTriggeredTTY: "/dev/ttys005",
                lastErrorDescription: nil
            ),
            permissions: PermissionState(notificationsGranted: true, automationLikelyGranted: true),
            launchAtLoginEnabled: true,
            alertCooldown: 120
        )

        XCTAssertEqual(viewModel.summaryText, "Monitoring · 2 tracked · 1 waiting")
        XCTAssertEqual(viewModel.needsAttentionRows.map(\.title), ["Window 2 / Tab 3"])
        XCTAssertEqual(viewModel.allMonitoredRows.map(\.title), ["Window 1 / Tab 1", "Window 2 / Tab 3"])
        XCTAssertNil(viewModel.needsAttentionEmptyText)
        XCTAssertEqual(viewModel.alertCooldownSeconds, 120)

        viewModel.apply(
            status: MonitorStatus(
                isRunning: true,
                isMuted: false,
                trackedSessionCount: 1,
                waitingSessionCount: 0,
                tabs: [
                    MonitoredTabState(
                        id: "1",
                        windowID: 1,
                        tabIndex: 1,
                        agent: .codex,
                        state: .running,
                        isCoolingDown: false
                    )
                ],
                lastTriggeredTTY: nil,
                lastErrorDescription: nil
            ),
            permissions: PermissionState(notificationsGranted: false, automationLikelyGranted: false),
            launchAtLoginEnabled: false,
            alertCooldown: 60
        )

        XCTAssertEqual(
            viewModel.needsAttentionEmptyText,
            "No tracked tabs need attention right now. Monitoring is still active."
        )
        XCTAssertEqual(viewModel.notificationsStatusText, "Missing")
        XCTAssertEqual(viewModel.automationStatusText, "Needs Approval")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/DashboardViewModelTests/test_applyBuildsAlertFirstSectionsAndEmptyState`

Expected: FAIL with errors like `Cannot find 'DashboardViewModel' in scope` and `Cannot infer key path type from context`.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/App/Dashboard/DashboardViewModel.swift
import Combine
import Foundation

struct DashboardRow: Identifiable, Equatable {
    let id: String
    let windowID: Int
    let tabIndex: Int
    let title: String
    let badge: String
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var summaryText = "Paused · 0 tracked · 0 waiting"
    @Published private(set) var needsAttentionRows: [DashboardRow] = []
    @Published private(set) var allMonitoredRows: [DashboardRow] = []
    @Published private(set) var needsAttentionEmptyText: String?
    @Published private(set) var notificationsStatusText = "Unknown"
    @Published private(set) var automationStatusText = "Unknown"
    @Published private(set) var launchAtLoginEnabled = false
    @Published var isMuted = false
    @Published var alertCooldownSeconds: TimeInterval = 60
    @Published var inlineErrorText: String?

    var onRowSelected: ((DashboardRow) -> Void)?
    var onMutedChanged: ((Bool) -> Void)?
    var onAlertCooldownChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggle: (() -> Void)?
    var onTestMoo: (() -> Void)?

    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    ) {
        summaryText = "\(status.isRunning ? "Monitoring" : "Paused") · \(status.trackedSessionCount) tracked · \(status.waitingSessionCount) waiting"

        let rows = status.tabs.map {
            DashboardRow(
                id: $0.id,
                windowID: $0.windowID,
                tabIndex: $0.tabIndex,
                title: $0.title,
                badge: $0.isWaiting ? "Waiting" : "Running"
            )
        }

        needsAttentionRows = rows.filter { $0.badge == "Waiting" }
        allMonitoredRows = rows
        needsAttentionEmptyText = needsAttentionRows.isEmpty
            ? "No tracked tabs need attention right now. Monitoring is still active."
            : nil

        notificationsStatusText = permissions.notificationsGranted ? "Granted" : "Missing"
        automationStatusText = permissions.automationLikelyGranted ? "Granted" : "Needs Approval"
        self.launchAtLoginEnabled = launchAtLoginEnabled
        isMuted = status.isMuted
        alertCooldownSeconds = alertCooldown
        inlineErrorText = status.lastErrorDescription
    }

    func select(_ row: DashboardRow) {
        onRowSelected?(row)
    }
}
```

```swift
// AgentNotify/App/Dashboard/DashboardView.swift
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.summaryText)
                .font(.headline)

            section("Needs Attention") {
                if let empty = viewModel.needsAttentionEmptyText {
                    Text(empty)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.needsAttentionRows) { row in
                        Button {
                            viewModel.select(row)
                        } label: {
                            HStack {
                                Text(row.title)
                                Spacer()
                                Text(row.badge)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            section("All Monitored") {
                ForEach(viewModel.allMonitoredRows) { row in
                    Button {
                        viewModel.select(row)
                    } label: {
                        HStack {
                            Text(row.title)
                            Spacer()
                            Text(row.badge)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            section("Settings") {
                Toggle("Mute Alerts", isOn: Binding(
                    get: { viewModel.isMuted },
                    set: {
                        viewModel.isMuted = $0
                        viewModel.onMutedChanged?($0)
                    }
                ))

                HStack {
                    Text("Alert Cooldown")
                    Spacer()
                    Picker("Alert Cooldown", selection: Binding(
                        get: { Int(viewModel.alertCooldownSeconds) },
                        set: { value in
                            viewModel.alertCooldownSeconds = TimeInterval(value)
                            viewModel.onAlertCooldownChanged?(TimeInterval(value))
                        }
                    )) {
                        Text("15s").tag(15)
                        Text("30s").tag(30)
                        Text("60s").tag(60)
                        Text("120s").tag(120)
                        Text("300s").tag(300)
                    }
                    .labelsHidden()
                }

                Text("Notifications: \(viewModel.notificationsStatusText)")
                Text("Automation: \(viewModel.automationStatusText)")

                Toggle("Launch at Login", isOn: Binding(
                    get: { viewModel.launchAtLoginEnabled },
                    set: { _ in viewModel.onLaunchAtLoginToggle?() }
                ))

                Button("Test Moo") {
                    viewModel.onTestMoo?()
                }
            }

            if let error = viewModel.inlineErrorText {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
        }
    }
}
```

```swift
// AgentNotify/App/Dashboard/DashboardWindowController.swift
import AppKit
import SwiftUI

protocol DashboardPresenting: AnyObject {
    func show()
    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    )
    func showInlineError(_ message: String?)
    var onRowSelected: ((DashboardRow) -> Void)? { get set }
    var onMutedChanged: ((Bool) -> Void)? { get set }
    var onAlertCooldownChanged: ((TimeInterval) -> Void)? { get set }
    var onLaunchAtLoginToggle: (() -> Void)? { get set }
    var onTestMoo: (() -> Void)? { get set }
}

@MainActor
final class DashboardWindowController: NSObject, DashboardPresenting {
    private let viewModel = DashboardViewModel()

    private lazy var window: NSWindow = {
        let controller = NSHostingController(rootView: DashboardView(viewModel: viewModel))
        let window = NSWindow(contentViewController: controller)
        window.title = "AgentNotify"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        return window
    }()

    var onRowSelected: ((DashboardRow) -> Void)? {
        get { viewModel.onRowSelected }
        set { viewModel.onRowSelected = newValue }
    }

    var onMutedChanged: ((Bool) -> Void)? {
        get { viewModel.onMutedChanged }
        set { viewModel.onMutedChanged = newValue }
    }

    var onAlertCooldownChanged: ((TimeInterval) -> Void)? {
        get { viewModel.onAlertCooldownChanged }
        set { viewModel.onAlertCooldownChanged = newValue }
    }

    var onLaunchAtLoginToggle: (() -> Void)? {
        get { viewModel.onLaunchAtLoginToggle }
        set { viewModel.onLaunchAtLoginToggle = newValue }
    }

    var onTestMoo: (() -> Void)? {
        get { viewModel.onTestMoo }
        set { viewModel.onTestMoo = newValue }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func apply(
        status: MonitorStatus,
        permissions: PermissionState,
        launchAtLoginEnabled: Bool,
        alertCooldown: TimeInterval
    ) {
        viewModel.apply(
            status: status,
            permissions: permissions,
            launchAtLoginEnabled: launchAtLoginEnabled,
            alertCooldown: alertCooldown
        )
    }

    func showInlineError(_ message: String?) {
        viewModel.inlineErrorText = message
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/DashboardViewModelTests/test_applyBuildsAlertFirstSectionsAndEmptyState`

Expected: PASS with `Executed 1 test, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add AgentNotify/App/Dashboard/DashboardViewModel.swift AgentNotify/App/Dashboard/DashboardView.swift AgentNotify/App/Dashboard/DashboardWindowController.swift AgentNotifyTests/App/DashboardViewModelTests.swift
git commit -m "feat: add dashboard window shell"
```

### Task 4: Add Terminal Navigation and Wire the Menu Bar to the Dashboard

**Files:**
- Modify: `AgentNotify/App/AppDelegate.swift`
- Modify: `AgentNotify/App/MenuBarController.swift`
- Create: `AgentNotify/Infra/Terminal/TerminalNavigator.swift`
- Modify: `README.md`
- Create: `AgentNotifyTests/App/MenuBarControllerTests.swift`
- Create: `AgentNotifyTests/Terminal/TerminalNavigatorTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AgentNotify

private final class CapturingAppleScriptRunner: AppleScriptRunning {
    var scripts: [(String, OsaLanguage)] = []

    func run(_ script: String, language: OsaLanguage) throws -> String {
        scripts.append((script, language))
        return ""
    }
}

private final class SpyDashboardPresenter: DashboardPresenting {
    var showCount = 0
    var lastInlineError: String?
    var onRowSelected: ((DashboardRow) -> Void)?
    var onMutedChanged: ((Bool) -> Void)?
    var onAlertCooldownChanged: ((TimeInterval) -> Void)?
    var onLaunchAtLoginToggle: (() -> Void)?
    var onTestMoo: (() -> Void)?

    func show() { showCount += 1 }
    func apply(status: MonitorStatus, permissions: PermissionState, launchAtLoginEnabled: Bool, alertCooldown: TimeInterval) {}
    func showInlineError(_ message: String?) { lastInlineError = message }
}

private struct StaticPoller: TerminalPolling {
    let snapshots: [TerminalTabSnapshot]

    func poll() throws -> [TerminalTabSnapshot] {
        snapshots
    }
}

private struct FailingNavigator: TerminalNavigating {
    func focus(windowID: Int, tabIndex: Int) throws {
        throw AppleScriptRunnerError.executionFailed("No such tab")
    }
}

private final class InMemoryMonitorSettingsStore: MonitorSettingsStoring {
    var isMuted = false
    var alertCooldown: TimeInterval = 60
}

final class TerminalNavigatorTests: XCTestCase {
    func test_focusBuildsAppleTerminalSelectionScript() throws {
        let runner = CapturingAppleScriptRunner()
        let navigator = TerminalNavigator(runner: runner)

        try navigator.focus(windowID: 12, tabIndex: 3)

        XCTAssertEqual(runner.scripts.count, 1)
        XCTAssertEqual(runner.scripts.first?.1, .appleScript)
        XCTAssertTrue(runner.scripts.first?.0.contains("window id 12") == true)
        XCTAssertTrue(runner.scripts.first?.0.contains("selected tab of front window to tab 3") == true)
    }
}

final class MenuBarControllerTests: XCTestCase {
    func test_primaryClickShowsDashboard() {
        let presenter = SpyDashboardPresenter()
        let settingsStore = InMemoryMonitorSettingsStore()
        let monitorController = MonitorController(
            poller: StaticPoller(snapshots: []),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 3)),
            notifier: SpyNotifier(),
            soundPlayer: SpySoundPlayer(),
            settingsStore: settingsStore
        )
        let controller = MenuBarController(
            monitorController: monitorController,
            dashboardPresenter: presenter,
            terminalNavigator: FailingNavigator(),
            settingsStore: settingsStore
        )

        controller.openDashboard()

        XCTAssertEqual(presenter.showCount, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/TerminalNavigatorTests/test_focusBuildsAppleTerminalSelectionScript -only-testing:AgentNotifyTests/MenuBarControllerTests/test_primaryClickShowsDashboard`

Expected: FAIL with errors like `Cannot find type 'TerminalNavigating' in scope`, `Cannot find 'TerminalNavigator' in scope`, and `Extra arguments at positions ... in call` for the new `MenuBarController` initializer.

- [ ] **Step 3: Write minimal implementation**

```swift
// AgentNotify/Infra/Terminal/TerminalNavigator.swift
import Foundation

protocol TerminalNavigating {
    func focus(windowID: Int, tabIndex: Int) throws
}

struct TerminalNavigator: TerminalNavigating {
    let runner: AppleScriptRunning

    init(runner: AppleScriptRunning = AppleScriptRunner()) {
        self.runner = runner
    }

    func focus(windowID: Int, tabIndex: Int) throws {
        let script = """
        tell application "Terminal"
            activate
            set frontWindow to first window whose id is \(windowID)
            set index of frontWindow to 1
            set selected tab of frontWindow to tab \(tabIndex) of frontWindow
        end tell
        """

        _ = try runner.run(script, language: .appleScript)
    }
}
```

```swift
// AgentNotify/App/MenuBarController.swift
import AppKit

final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let monitorController: MonitorController
    private let permissionCoordinator: PermissionCoordinator
    private let launchAtLoginController: LaunchAtLoginController
    private let settingsStore: MonitorSettingsStoring
    private let dashboardPresenter: DashboardPresenting
    private let terminalNavigator: TerminalNavigating

    private var latestStatus = MonitorStatus(
        isRunning: false,
        isMuted: false,
        trackedSessionCount: 0,
        waitingSessionCount: 0,
        tabs: [],
        lastTriggeredTTY: nil,
        lastErrorDescription: nil
    )

    init(
        monitorController: MonitorController,
        permissionCoordinator: PermissionCoordinator = PermissionCoordinator(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController(),
        settingsStore: MonitorSettingsStoring = MonitorSettingsStore(),
        dashboardPresenter: DashboardPresenting = DashboardWindowController(),
        terminalNavigator: TerminalNavigating = TerminalNavigator()
    ) {
        self.monitorController = monitorController
        self.permissionCoordinator = permissionCoordinator
        self.launchAtLoginController = launchAtLoginController
        self.settingsStore = settingsStore
        self.dashboardPresenter = dashboardPresenter
        self.terminalNavigator = terminalNavigator
        super.init()

        self.monitorController.onStatusChange = { [weak self] status in
            self?.latestStatus = status
            self?.refreshDashboard()
        }

        self.dashboardPresenter.onRowSelected = { [weak self] row in
            self?.focus(row: row)
        }
        self.dashboardPresenter.onMutedChanged = { [weak self] muted in
            self?.monitorController.setMuted(muted)
        }
        self.dashboardPresenter.onAlertCooldownChanged = { [weak self] cooldown in
            self?.monitorController.setAlertCooldown(cooldown)
            self?.refreshDashboard()
        }
        self.dashboardPresenter.onLaunchAtLoginToggle = { [weak self] in
            self?.toggleLaunchAtLogin()
        }
        self.dashboardPresenter.onTestMoo = { [weak self] in
            self?.monitorController.playTestSound()
        }
    }

    func start() {
        configureStatusItem()
        monitorController.start(pollInterval: 2)
    }

    func openDashboard() {
        dashboardPresenter.show()
        refreshDashboard()
    }

    @objc
    internal func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let eventType = NSApp.currentEvent?.type
        if eventType == .rightMouseUp {
            statusItem.popUpMenu(makeContextMenu())
            return
        }

        openDashboard()
    }

    private func configureStatusItem() {
        statusItem.button?.title = "Moo"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(handleStatusItemClick(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(
            withTitle: monitorController.isRunning ? "Stop Monitoring" : "Start Monitoring",
            action: #selector(toggleMonitoring),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: monitorController.isMuted ? "Unmute Alerts" : "Mute Alerts",
            action: #selector(toggleMute),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.items.forEach { $0.target = self }
        return menu
    }

    private func refreshDashboard() {
        Task { [weak self] in
            guard let self else { return }
            let permissions = await permissionCoordinator.currentState()
            await MainActor.run {
                dashboardPresenter.apply(
                    status: latestStatus,
                    permissions: permissions,
                    launchAtLoginEnabled: launchAtLoginController.isEnabled,
                    alertCooldown: settingsStore.alertCooldown
                )
            }
        }
    }

    private func focus(row: DashboardRow) {
        do {
            try terminalNavigator.focus(windowID: row.windowID, tabIndex: row.tabIndex)
            dashboardPresenter.showInlineError(nil)
        } catch {
            dashboardPresenter.showInlineError("That Terminal tab is no longer available.")
        }
    }

    @objc
    private func toggleMonitoring() {
        if monitorController.isRunning {
            monitorController.stop()
        } else {
            monitorController.start(pollInterval: 2)
        }
        refreshDashboard()
    }

    @objc
    private func toggleMute() {
        monitorController.setMuted(!monitorController.isMuted)
        refreshDashboard()
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginController.isEnabled {
                try launchAtLoginController.disable()
            } else {
                try launchAtLoginController.enable()
            }
            dashboardPresenter.showInlineError(nil)
        } catch {
            dashboardPresenter.showInlineError("Could not update Launch at Login.")
        }
        refreshDashboard()
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

        let settingsStore = MonitorSettingsStore()
        let monitorController = MonitorController(
            poller: TerminalPoller(runner: AppleScriptRunner()),
            tracker: SessionTracker(detector: NeedsInputDetector(quietPeriod: 3)),
            notifier: NotificationService(),
            soundPlayer: SoundPlayer(),
            settingsStore: settingsStore
        )

        menuBarController = MenuBarController(
            monitorController: monitorController,
            settingsStore: settingsStore,
            dashboardPresenter: DashboardWindowController(),
            terminalNavigator: TerminalNavigator()
        )
        menuBarController?.start()
    }
}
```

```markdown
<!-- README.md -->
## Dashboard

- Left-click `Moo` to open the dashboard window.
- The dashboard shows `Needs Attention`, `All Monitored`, and `Settings`.
- Click any `Window X / Tab Y` row to jump straight to that Terminal tab.
- Right-click `Moo` to open the utility context menu.
```

- [ ] **Step 4: Run tests and verify the app still builds**

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS' -only-testing:AgentNotifyTests/TerminalNavigatorTests/test_focusBuildsAppleTerminalSelectionScript -only-testing:AgentNotifyTests/MenuBarControllerTests/test_primaryClickShowsDashboard`

Run: `xcodebuild test -scheme AgentNotify -destination 'platform=macOS'`

Run: `xcodebuild -scheme AgentNotify -destination 'platform=macOS' build`

Expected:
- targeted tests PASS
- full test suite PASS
- final build ends with `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add README.md AgentNotify/App/AppDelegate.swift AgentNotify/App/MenuBarController.swift AgentNotify/Infra/Terminal/TerminalNavigator.swift AgentNotifyTests/App/MenuBarControllerTests.swift AgentNotifyTests/Terminal/TerminalNavigatorTests.swift
git commit -m "feat: open dashboard from menu bar and focus terminal tabs"
```

## Self-Review

### Spec coverage

- dashboard opens only when `Moo` is clicked: covered in Task 4
- alert-first layout with `Needs Attention`, `All Monitored`, `Settings`: covered in Task 3
- row labels use `Window X / Tab Y`: covered in Task 1 and Task 3
- click-to-focus Terminal navigation: covered in Task 4
- empty state when nothing needs attention: covered in Task 3
- persisted mute and alert cooldown: covered in Task 2
- visible permission state and launch-at-login status: covered in Task 3 and Task 4
- menu bar utility stays responsive while monitoring: covered in Task 2

### Placeholder scan

- no `TODO`, `TBD`, or “implement later” placeholders remain
- each task includes exact files, code, commands, and expected outcomes

### Type consistency

- `TrackedSession.locationLabel`, `MonitoredTabState.title`, and `DashboardRow.title` all use the same `Window X / Tab Y` format
- `MonitorStatus` is the single published snapshot from `MonitorController`
- `DashboardPresenting` and `TerminalNavigating` are the injected boundaries used by `MenuBarController`
