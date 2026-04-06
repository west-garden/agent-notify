# AgentNotify Cow Icon Design

Date: 2026-04-06
Product: AgentNotify
Platform: macOS
Related specs:
- `docs/superpowers/specs/2026-04-06-terminal-agent-notify-design.md`
- `docs/superpowers/specs/2026-04-06-dashboard-window-design.md`

## Goal

Give AgentNotify a recognizable cow-themed visual identity that works in both of these places:

- the macOS menu bar status item
- the app icon shown in Finder, Launchpad, Spotlight, and app switch surfaces

The result should feel playful and memorable without hurting small-size legibility.

## Problem Statement

The current build has no custom app icon and the menu bar entry is text-only:

- the app looks unfinished in macOS surfaces
- the top bar label `Moo` consumes space and depends on text recognition
- the product already uses cow language and sound, but the visual layer does not match

The icon work should make the product easier to spot at a glance and more coherent as a small utility.

## Chosen Visual Direction

The chosen direction is:

- a cute, slightly goofy cartoon cow head
- warm cream-orange rounded-square background
- black-and-white face with a soft pink nose
- small horns, rounded eyes, and simple cheek/ear shapes
- expressive enough to feel friendly, but simple enough to survive tiny sizes

The tone should be “adorable utility,” not mascot-heavy branding and not flat corporate geometry.

## Alternatives Considered

### 1. Minimal line icon

Pros:

- very clean
- easy to scale down

Cons:

- loses the playful personality the user asked for
- risks looking generic in a crowded menu bar

Decision: rejected.

### 2. Flat solid glyph

Pros:

- strong silhouette
- easier to implement than a character face

Cons:

- less charming than a character head
- harder to make feel distinctly “cow” without adding awkward detail

Decision: rejected.

### 3. Cartoon cow head on colored tile

Pros:

- fits the product name and alert sound
- can look friendly and distinctive
- works for both app icon and menu bar with one shared visual system

Cons:

- requires a simplified small-size variant to avoid visual mush

Decision: selected.

## Asset Strategy

Use one shared visual system with two output targets.

### App icon

- Use the full-color cow head centered on a warm cream-orange rounded square.
- Keep the face large enough that the nose and horns still read at small macOS icon sizes.
- Do not add text, shadows, or decorative scene elements.

### Menu bar icon

- Use the same cow head and color family, but simplify the drawing for tiny display.
- Remove any detail that does not survive at menu bar scale.
- Prefer a compact head-only silhouette instead of the full rounded-square tile if the tile makes the icon look cramped.

This keeps the product visually coherent while respecting the different display constraints.

## Product Behavior Changes

### Menu bar presentation

- Replace the text-only `Moo` status item with an icon-first status item.
- Keep the menu bar hit target and left/right click behavior unchanged.
- Preserve an accessibility label and tooltip so the item is still identifiable to screen readers and hover users.

### App identity

- Add a real app icon so the built app no longer uses the default generic icon.

## Technical Direction

The current project has no asset catalog. The icon work should introduce one rather than scattering icon files across generic resources.

### Resource structure

- Add `Assets.xcassets` to the app target.
- Create an `AppIcon.appiconset` for the macOS app icon.
- Add a dedicated image set for the menu bar icon.
- Keep a single editable source asset in the repo so exported sizes can be regenerated consistently.

### Rendering approach

- Create a master vector-style source for the cow artwork.
- Export the required raster sizes for the app icon set.
- Export a separate small-size menu bar asset tuned for clarity instead of blindly reusing the large icon.

This favors deterministic repo-native assets over opaque generated binaries.

## Visual Constraints

The icon set should follow these constraints:

- no text inside the icon
- no photorealistic rendering
- no gradients that blur the face at small sizes
- no tiny facial details that disappear below menu bar size
- no overly saturated background color
- no dark-mode-specific variant in v1 unless testing shows the chosen icon disappears in one menu bar mode

## Accessibility And Usability

- The menu bar item should remain easy to identify when color is not the only cue.
- The cow face silhouette should still read if the menu bar compresses or the display scales down.
- If the color icon proves too noisy in the menu bar during verification, fallback is to keep the same cow face but reduce saturation and detail, not to revert to text-only.

## Testing

Verification should cover:

- the app builds with the new asset catalog wiring
- the menu bar item uses the image instead of the `Moo` title
- the app bundle exposes the custom app icon
- the menu bar icon is still recognizable in light and dark appearances
- existing left-click dashboard open and right-click context menu behavior still work

## Out Of Scope

- animated icons
- multiple selectable icon themes
- alternate holiday or novelty variants
- icon picker in settings
