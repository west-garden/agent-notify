# AgentNotify

Menu bar monitor for Apple Terminal sessions running `claude` and `codex`.

## What It Does

- Watches Apple Terminal tabs without changing how you launch agents.
- Detects when a `claude` or `codex` session has stopped and is waiting for your next input.
- Sends a macOS notification and plays a bundled `moo.wav` alert once per waiting cycle.
- Shows current monitor status, tracked tab count, last alert, mute, and launch-at-login controls in the menu bar.

## Requirements

- macOS with Apple Terminal
- Full Xcode
- `xcodegen`

## Running

1. `brew install xcodegen`
2. `xcodegen generate`
3. Open `AgentNotify.xcodeproj`
4. Run the `AgentNotify` scheme once from Xcode
5. Approve macOS prompts as they appear

## Permissions

- Grant Notification permission so macOS alerts can appear.
- Grant Automation access when macOS asks to let AgentNotify control Terminal.
- If Terminal polling fails, the menu bar status changes to an error state instead of failing silently.

## Menu Bar

- `Start Monitoring` / `Stop Monitoring` controls the poll loop.
- `Mute Alerts` silences notifications and the cow sound without stopping monitoring.
- `Enable Launch at Login` toggles startup registration through `SMAppService`.
- `Tracked Tabs` and `Last Alert` help you find the tab that needs attention.

## Verification

- `xcodebuild test -scheme AgentNotify -destination 'platform=macOS'`
- `xcodebuild -scheme AgentNotify -destination 'platform=macOS' build`
