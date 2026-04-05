import Foundation

protocol TerminalPolling {
    func poll() throws -> [TerminalTabSnapshot]
}

extension TerminalPoller: TerminalPolling {}

struct MonitorStatus {
    let isRunning: Bool
    let isMuted: Bool
    let trackedSessionCount: Int
    let lastTriggeredTTY: String?
    let lastErrorDescription: String?
}

final class MonitorController {
    private let poller: TerminalPolling
    private let tracker: SessionTracker
    private let notifier: Notifying
    private let soundPlayer: SoundPlaying

    private(set) var isRunning = false
    private(set) var isMuted = false
    private(set) var trackedSessionCount = 0
    private(set) var lastTriggeredTTY: String?
    private(set) var lastErrorDescription: String?

    var onStatusChange: ((MonitorStatus) -> Void)?

    private var timer: Timer?

    init(poller: TerminalPolling, tracker: SessionTracker, notifier: Notifying, soundPlayer: SoundPlaying) {
        self.poller = poller
        self.tracker = tracker
        self.notifier = notifier
        self.soundPlayer = soundPlayer
    }

    deinit {
        stop()
    }

    func start(pollInterval: TimeInterval) {
        guard !isRunning else {
            return
        }

        isRunning = true
        publishStatus()

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = min(0.5, pollInterval / 4)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        guard isRunning else {
            return
        }

        isRunning = false
        publishStatus()
    }

    func setMuted(_ muted: Bool) {
        guard isMuted != muted else {
            return
        }

        isMuted = muted
        publishStatus()
    }

    func tick(now: Date = .now) {
        do {
            let snapshots = try poller.poll()
            var trackedCount = 0

            for snapshot in snapshots {
                guard let event = tracker.process(snapshot: snapshot, now: now) else {
                    continue
                }

                trackedCount += 1

                guard let payload = event.notification else {
                    continue
                }

                lastTriggeredTTY = payload.tty

                guard !isMuted else {
                    continue
                }

                notifier.notify(payload)
                soundPlayer.playCowSound()
            }

            trackedSessionCount = trackedCount
            lastErrorDescription = nil
        } catch {
            trackedSessionCount = 0
            lastErrorDescription = error.localizedDescription
        }

        publishStatus()
    }

    private func publishStatus() {
        onStatusChange?(MonitorStatus(
            isRunning: isRunning,
            isMuted: isMuted,
            trackedSessionCount: trackedSessionCount,
            lastTriggeredTTY: lastTriggeredTTY,
            lastErrorDescription: lastErrorDescription
        ))
    }
}
