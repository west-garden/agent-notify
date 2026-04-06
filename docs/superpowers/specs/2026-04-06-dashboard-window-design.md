# AgentNotify Dashboard Window Design

Date: 2026-04-06
Product: AgentNotify
Platform: macOS
Related spec: `docs/superpowers/specs/2026-04-06-terminal-agent-notify-design.md`

## Goal

Add a visible, usable control surface to the existing menu bar monitor so the user can:

- see which Terminal tabs currently need attention
- see all tracked agent tabs in one place
- jump straight to a specific `Window X / Tab Y`
- change a small set of operational settings without editing code or guessing whether the app is healthy

The monitor remains a lightweight menu bar utility. This design adds a small dashboard window, not a full desktop app.

## Problem Statement

The current build behaves like a pure accessory app:

- launching it does not open a visible window
- the only visible affordance is the `Moo` status item in the menu bar
- status is compressed into menu text instead of a scannable dashboard
- the user cannot easily tell which Terminal tab is waiting
- the user cannot click a tracked tab to jump directly to it

This makes the app feel unresponsive even when it is running correctly.

## Chosen Product Shape

The chosen shape is:

- keep the app as a menu bar utility
- clicking the `Moo` status item opens a small dashboard window
- the dashboard is the primary control surface
- no window opens automatically on launch
- the dashboard focuses on current state, not event history

## Alternatives Considered

### 1. `NSPopover` from the menu bar

Pros:

- very lightweight
- natural for quick status checks

Cons:

- cramped for two lists plus settings
- harder to scale once click-to-focus and richer states are added
- more awkward for inline error and empty states

Decision: rejected.

### 2. Menu bar app plus a small dashboard window

Pros:

- enough room for alert-first layout
- easy to reopen from the menu bar
- still feels like a utility, not a full app
- supports future growth without redesigning the whole shell

Cons:

- slightly heavier than a popover

Decision: selected.

### 3. Full main-window app with menu bar integration

Pros:

- maximum space and flexibility

Cons:

- too heavy for this tool
- pushes the product toward a general desktop app before it earns that complexity

Decision: rejected.

## User Experience

### Open behavior

- App launch does not auto-open any window.
- Clicking the menu bar `Moo` item opens the dashboard window.
- If the dashboard is already open, clicking `Moo` brings it to the front instead of creating duplicates.

### Dashboard layout

The layout is alert-first and has three sections in this order:

1. Summary header
2. `Needs Attention`
3. `All Monitored`
4. `Settings`

### Summary header

The top line shows:

- monitor state: `Monitoring` or `Paused`
- tracked tab count
- waiting tab count

This gives a quick answer to “is it running” and “is anything blocked” before the user reads the lists.

### `Needs Attention`

This section is the highest-priority area.

- It shows only tracked tabs currently in `Waiting`.
- Each row is rendered as `Window X / Tab Y`.
- Rows are clickable and switch Terminal to that exact tab.
- The section remains visible even when empty.
- Empty state text should explicitly say that no tracked tab currently needs attention and monitoring is still active.

### `All Monitored`

This section shows all tracked agent tabs, whether or not they need attention.

- Each row is rendered as `Window X / Tab Y`.
- Each row shows a status badge: `Running` or `Waiting`.
- Rows are clickable and use the same navigation behavior as the alert list.

The goal is to let the user understand both the urgent queue and the broader monitored set without switching views.

### `Settings`

First-version controls:

- `Mute Alerts`
- `Launch at Login`
- `Notifications` permission state
- `Automation` permission state
- `Test Moo` button
- `Alert Cooldown`

All settings persist locally across restarts.

## Interaction Model

### Row click behavior

Clicking a tracked tab row does the following:

1. Activates Apple Terminal
2. Brings the target window to the front
3. Selects the target tab

If navigation fails because the window or tab no longer exists:

- show a lightweight inline error in the dashboard
- remove the stale row on the next successful poll

### Empty state behavior

When no tab is waiting:

- `Needs Attention` stays visible
- show an empty-state message instead of collapsing the section

This preserves layout stability and avoids making the dashboard jump as sessions change.

## State Model

The dashboard depends on three session-level states:

- `Running`: tracked agent session is active and not currently waiting
- `Waiting`: tracked agent session is alive and waiting for user input
- `Stale`: a previously tracked session is no longer valid because the tab closed or is no longer a tracked agent tab

`Stale` is an internal cleanup state, not a visible badge. Stale rows disappear from the dashboard.

## Alert Semantics

The existing one-alert-per-wait-cycle rule stays in place.

Additional rule for this design:

- add a global alert cooldown to reduce clustered notifications when multiple tabs enter `Waiting` close together

Cooldown behavior:

- the first eligible waiting tab alerts immediately
- if another tab enters `Waiting` during cooldown, its alert is delayed rather than dropped
- once cooldown expires, the delayed tab may alert if it is still in `Waiting` and has not been alerted for that wait cycle
- if a tab returns to `Running` and later re-enters `Waiting`, it becomes eligible for a new alert cycle

This preserves signal quality without losing waiting tabs entirely.

## Architecture Changes

The current code already has a working monitor, menu bar item, and notification path. This design adds a UI layer and a few support services.

### 1. Dashboard window controller

Add a dedicated controller that owns a single dashboard window:

- creates the window lazily on first open
- reuses the same window instance
- brings the window forward on repeated open requests

### 2. Dashboard view model

Add a view model or state adapter that converts monitor state into display state:

- summary counts
- `Needs Attention` rows
- `All Monitored` rows
- empty-state and inline-error messages
- persisted settings values

### 3. Richer monitor snapshot

`MonitorController` currently exposes aggregate counters. It needs to publish row-level tracked session data so the dashboard can render actual tab lists.

Required output additions:

- `windowID`
- `tabIndex`
- current display state: `Running` or `Waiting`
- whether a row is currently alert-eligible or suppressed by cooldown

### 4. Terminal navigator

Add a small AppleScript-backed service for navigation:

- input: `windowID` and `tabIndex`
- output: success or failure

This service is separate from the polling code because reading Terminal state and controlling Terminal navigation are different responsibilities.

### 5. Settings store

Persist dashboard-backed settings in a lightweight local store, such as `UserDefaults`.

Required persisted values:

- mute on or off
- launch at login on or off
- alert cooldown duration

## Error Handling

The dashboard must not fail silently.

Visible error cases:

- missing notifications permission
- missing Terminal automation permission
- failed row navigation because the target tab disappeared
- polling failure

Behavior:

- permissions show as explicit status text in `Settings`
- row navigation failure surfaces as a lightweight inline message
- polling failure updates the summary state and preserves the last useful UI instead of blanking the entire dashboard

## Testing Strategy

### Unit tests

Add tests for:

- alert cooldown timing and delayed notification behavior
- dashboard state derivation from tracked sessions
- empty-state rendering rules
- stale session removal from visible lists

### Integration tests

Add tests for:

- menu bar open request creates one reusable dashboard window
- clicking a row calls Terminal navigation with the right `windowID` and `tabIndex`
- settings persist across relaunch

### Manual verification

Verify on a real Mac with Apple Terminal:

- launch app and confirm no window auto-opens
- click `Moo` and confirm the dashboard appears
- create multiple `codex` or `claude` tabs
- confirm `Needs Attention` and `All Monitored` stay in sync with live state
- click a row and confirm Terminal jumps to the correct tab
- force a missing-permission case and confirm the dashboard explains it clearly

## Out of Scope

The following are intentionally excluded from this design:

- event history or audit timeline
- free-form searchable logs UI
- support for iTerm, Warp, or other terminal apps
- custom row labels beyond `Window X / Tab Y`
- auto-opening the dashboard when an alert fires
- full preferences window separate from the dashboard

## Acceptance Criteria

This design is complete when all of the following are true:

- clicking `Moo` opens one reusable dashboard window
- the dashboard shows `Needs Attention`, `All Monitored`, and `Settings`
- both lists use `Window X / Tab Y` rows
- both lists support click-to-focus Terminal navigation
- `Needs Attention` remains visible with an empty state when nothing is waiting
- `Alert Cooldown` is user-configurable and persisted
- missing permissions are visible from the dashboard
- the menu bar monitor behavior continues to work without requiring a Dock-first app model
