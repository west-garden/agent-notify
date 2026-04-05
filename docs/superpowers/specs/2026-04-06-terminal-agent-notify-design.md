# Terminal Agent Notify Design

Date: 2026-04-06
Target platform: macOS
Terminal target: Apple Terminal
Agent targets: `claude` and `codex`

## Goal

Build a zero-intrusion macOS utility that monitors Apple Terminal tabs running `claude` or `codex` and notifies the user when an agent session is still alive but has stopped and is waiting for the user's next input.

The first version is optimized for this one event only:

- `NeedsInput`: the agent process is still running, but the UI has entered an input-ready state and is waiting for the user

The following event is explicitly out of scope for v1:

- `ReturnedToShell`: the agent process exits and the tab returns to the shell prompt

## Constraints

- No required change to the user's normal workflow
- No wrapper command requirement for `cs`, `csx`, `claude`, or `codex`
- No shell hook requirement for correctness in v1
- Must work with Apple Terminal, not iTerm or Warp
- Must notify only once per wait state to avoid spam
- Must favor low false-positive rate over aggressive alerting

## User Experience

### Primary flow

1. The user starts `claude`, `codex`, `cs`, or `csx` in any Apple Terminal tab.
2. The monitor app discovers that the tab is running a tracked agent.
3. While the agent is producing output, the tab is considered `Running`.
4. When the agent output becomes stable and the visible screen matches an input-ready pattern, the tab transitions to `NeedsInput`.
5. On the first transition into `NeedsInput`, the app sends a macOS notification and plays a custom cow sound.
6. If the user resumes work in that tab and output changes again, the tab returns to `Running`.
7. If the tab later becomes input-ready again, the app may notify again for that new cycle.

### Notification behavior

- Only `NeedsInput` triggers a notification in v1
- Notification is a combination of:
  - native macOS system notification
  - custom cow audio playback
- Each tab is debounced so one waiting state causes one alert
- A later `Running -> NeedsInput` transition may alert again

## Product Shape

The product is a small macOS menu bar application.

### Why menu bar app

- Feels like a persistent system utility instead of a one-shot script
- Works well with login auto-start
- Gives a place for lightweight status and controls without building a full app
- Avoids occupying the Dock

### v1 menu bar features

- Current monitor status
- Number of tracked Terminal tabs
- Last tab that triggered `NeedsInput`
- Mute or unmute notifications
- Quit action

## Architecture

The system has five main parts:

1. `TerminalPoller`
Reads Apple Terminal state on an interval and returns normalized snapshots of windows and tabs.

2. `SessionTracker`
Maps Terminal tabs to stable tracked sessions and stores the latest known state per tab.

3. `NeedsInputDetector`
Applies detection rules to decide whether a session is `Running` or `NeedsInput`.

4. `Notifier`
Sends macOS notifications and plays the cow sound.

5. `AppController`
Coordinates startup, permissions, polling, settings, and menu bar state.

## Terminal Integration

The app uses Apple Terminal scripting support to read:

- window and tab identity
- `tty`
- process list
- `busy` flag
- recent visible content for the tab
- optionally tab history when needed for debugging

This keeps the tool zero-intrusion: it observes Terminal instead of modifying how the user launches agents.

## Session Model

Each tracked session corresponds to one Terminal tab that is currently or recently running an agent.

Suggested identity:

- Terminal window id
- Terminal tab index or tab identifier
- `tty`

Stored session fields:

- tracked agent kind: `claude` or `codex`
- current state: `Unknown`, `Running`, `NeedsInput`
- last visible content fingerprint
- last content change timestamp
- last notification timestamp
- whether the current waiting cycle has already been notified

## Detection Strategy

`NeedsInput` is detected conservatively from a combination of signals. A tab must satisfy all required signals before it is considered waiting for user input.

### Required signals

1. Agent process still present
- The tab's process list includes a tracked agent process such as `claude` or `codex`.

2. Output has stabilized
- The visible tail content has not materially changed for a configured quiet period.
- Initial recommended quiet period: about 2 to 4 seconds, configurable.

3. UI appears input-ready
- The visible content tail matches agent-specific patterns that indicate the session is waiting for the next instruction.

### Agent-specific rule sets

`Claude` and `Codex` use different terminal interfaces, so they should not share one generic matcher.

Each agent gets its own matcher with:

- positive patterns that suggest input-ready state
- negative patterns that indicate active work, streaming output, or a modal state

Examples of positive signals may include:

- visible prompt area reappears
- stable footer or input hint is shown
- cursor placement or prompt framing matches idle state

Examples of negative signals may include:

- streaming logs
- progress text changing between polls
- plan mode interaction mid-render
- transient pauses during generation

The exact patterns should be developed from real captured samples from both tools.

### False-positive policy

The detector should prefer missing a few alerts over notifying too early.

Rules:

- Silence alone is not enough
- `busy = false` alone is not enough
- process presence alone is not enough
- the detector needs process presence plus quiet window plus input-ready pattern

## Polling Model

Initial recommendation:

- poll every 1 to 2 seconds
- compare a normalized tail snapshot of each tracked tab

Normalization should remove unstable noise when possible, such as:

- ANSI escape sequences
- trailing whitespace-only differences
- timestamps if any appear in tool output

This reduces false state flips caused by cosmetic redraws.

## Notification Design

### macOS notification

The notification should include:

- title such as `Agent Waiting`
- subtitle or body with agent type and Terminal tab identity
- short message that the session is waiting for input

Example:

- Title: `Codex Waiting`
- Body: `Terminal tab on /dev/ttys003 is waiting for your input.`

### Cow sound

The app bundles a local cow sound file such as `moo.wav`.

Behavior:

- play the custom cow sound on `NeedsInput`
- if the custom asset cannot be loaded, fall back to a standard system sound

The cow sound path may later become user-configurable, but v1 can ship with one bundled asset.

## Permissions

The app requires:

- Automation permission to control or read Apple Terminal through Apple events
- Notification permission to display system notifications

If permission is missing:

- the menu bar UI should show the missing capability clearly
- the app should not fail silently

## Settings

v1 settings can live in a lightweight local configuration store.

Required settings:

- poll interval
- quiet period duration
- notifications enabled or muted
- cow sound enabled

Optional future settings:

- custom sound file path
- per-agent enable or disable
- debug logging level

## Logging and Debugging

The app should keep a small local debug log explaining important transitions and suppressed notifications.

Useful entries:

- session discovered
- state changed to `Running`
- state changed to `NeedsInput`
- notification sent
- notification suppressed because the session was already notified
- permission error

This is important because classifier tuning will likely need iteration against real terminal samples.

## Implementation Notes

Recommended implementation language: `Swift`

Reasons:

- native macOS menu bar app support
- native notifications and audio playback
- no extra runtime dependency like Electron
- straightforward packaging for login item behavior

Likely frameworks:

- `AppKit` or `SwiftUI` app shell for menu bar behavior
- `UserNotifications` for notifications
- `AVFoundation` or `NSSound` for cow sound playback
- AppleScript execution or `NSAppleScript` bridge for Terminal polling

## Testing Strategy

### Detector tests

Build sample-based tests around real captured Terminal outputs from both `claude` and `codex`.

Test cases should cover:

- active streaming output stays `Running`
- temporary quiet periods during work do not trigger notification
- stable input-ready screen transitions to `NeedsInput`
- repeated polls in the same waiting state do not re-notify
- renewed output returns to `Running`

### Integration checks

Manual integration should validate:

- multiple Terminal tabs open at once
- mixed `claude` and `codex` sessions
- one tab waiting while another is still active
- notification delivery
- cow sound playback
- permission failure messaging

## Out of Scope for v1

- Monitoring iTerm, Warp, or other terminals
- OCR-based detection
- Shell hook or wrapper-based exact signaling
- Returned-to-shell notifications
- Historical dashboard of all completed tasks
- Mobile push notifications
- Cross-machine sync

## Open Decisions Already Resolved

- Terminal target: Apple Terminal only
- Intrusion model: zero-intrusion monitoring
- Primary event: `NeedsInput` only
- Notification style: macOS notification plus custom cow sound
- App shape: menu bar utility

## Delivery Plan Shape

After this design is approved, the implementation plan should likely proceed in stages:

1. Scaffold the macOS menu bar app
2. Add Terminal polling and normalized tab snapshots
3. Implement a simple session tracker
4. Implement `NeedsInput` detection with fixture-driven tests
5. Add notifications and bundled cow sound
6. Add permissions UX and menu bar controls
7. Run live verification against real Terminal tabs

## Risks

### Detection ambiguity

Agent interfaces may redraw subtly, and a pure observer approach cannot be perfectly exact.

Mitigation:

- agent-specific detectors
- conservative thresholds
- debug logging
- easy rule tuning

### Apple Terminal scripting limitations

Polling via AppleScript may be slower or less structured than a direct terminal integration.

Mitigation:

- small polling interval
- normalized snapshots
- minimal per-poll work

### Notification fatigue

Incorrect repeat alerts would make the tool unusable.

Mitigation:

- notify only on state transition into `NeedsInput`
- reset only after confirmed renewed activity

## Success Criteria

The first version is successful if:

- the user can keep using Apple Terminal normally
- the app automatically discovers `claude` and `codex` sessions
- the app plays a cow sound and shows a notification when a tracked session is waiting for the next input
- the same waiting state does not alert repeatedly
- false positives stay low enough that the user keeps the tool enabled
