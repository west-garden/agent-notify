# AgentNotify

Menu bar monitor for Apple Terminal sessions running `claude` and `codex`.

## What It Does

- Watches Apple Terminal tabs without changing how you launch agents.
- Detects when a `claude` or `codex` session has stopped and is waiting for your next input.
- Sends a macOS notification and plays a bundled `moo.wav` alert once per waiting cycle.
- Opens a dashboard window with `Needs Attention`, `All Monitored`, and `Settings`.
- Lets you click any `Window X / Tab Y` row to jump straight to that Terminal tab.

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

- Left-click the cow icon to open the dashboard window.
- Right-click the cow icon to open the utility context menu.
- `Start Monitoring` / `Stop Monitoring` controls the poll loop.
- `Mute Alerts` silences notifications and the cow sound without stopping monitoring.

## Dashboard

- `Needs Attention` shows only tabs waiting for your next input.
- `All Monitored` shows every tracked `claude` or `codex` tab.
- `Settings` includes mute, launch at login, permission state, `Test Moo`, and alert cooldown.

## Verification

- `xcodebuild test -scheme AgentNotify -destination 'platform=macOS'`
- `xcodebuild -scheme AgentNotify -destination 'platform=macOS' build`
