# Orbit Design System & Style Guide

Use this document to replicate the exact visual identity of the Orbit app in any new SwiftUI project.

---

## 1. Philosophy

Minimal, monochromatic, data-dense. The interface is strictly black-and-white with no accent colors. Information hierarchy is communicated through font size, weight, and opacity — never through color. Every element earns its place; nothing is decorative.

---

## 2. Color Palette

| Token | Value | Usage |
|---|---|---|
| Background | `Color.black` | Full-bleed on every screen, applied via `Color.black.ignoresSafeArea()` |
| Primary text | `Color.white` | Titles, values, active elements |
| Secondary text | `Color.gray` (system) | Labels, subtitles, metadata |
| Muted text / icons | `Color.white.opacity(0.25)` | Inactive states, unchecked toggles, dim elements |
| Surface / card fill | `Color.white.opacity(0.06)` | Card backgrounds, list row backgrounds |
| Input field fill | `Color.white.opacity(0.08)` | Text field backgrounds |
| Divider | `Color.white.opacity(0.08–0.1)` | Subtle separators between list items |
| Completion indicator | `Color.white` (not green/blue) | Filled circles, active segments, calendar tiles |

**Rule:** Never use system accent colors, tints, or any hue. The entire palette is black → white with opacity variations. Toggle tints are `.white`. Progress bars are `.white`. Everything is monochromatic.

---

## 3. Typography

**One font family only: SF Mono** (Apple's monospaced system font).

```swift
enum AppFont {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
```

### Type Scale

| Role | Size | Weight | Example |
|---|---|---|---|
| Hero / date number | 42 | `.bold` | "14" (selected date) |
| Large stat value | 28 | `.bold` | "12" (streak count) |
| Day number (calendar strip) | 22 | `.bold` | "7" |
| Habit name | 20 | `.bold` | "Exercise" |
| Weekday in header | 20 | `.regular` | "Wednesday" |
| Expanded DI counter | 18 | `.bold` | "3/5" |
| Body / form input | 18 | `.medium` | Text field content |
| List row text | 15 | `.regular` | Settings labels |
| Compact DI text | 13–14 | `.semibold`–`.bold` | "Orbit", "3/5" |
| Progress ring counter | 13 | `.semibold` | "2/4" |
| Section header / label | 11–12 | `.medium` | "OVERVIEW", "CURRENT STREAK" |
| Micro label / caption | 10–11 | `.medium`/`.regular` | "days", "Missed", "Completed" |

### Letter Spacing

All-caps labels use explicit kerning for a tracked-out look:
- Section headers: `kerning(1.2)` to `kerning(2.0)`
- Streak subtitle: `kerning(1.5)` — e.g. `"3  DAYS  STREAK"`

---

## 4. Layout & Spacing

### Global
- Horizontal page padding: **24pt** on both sides, used consistently across all screens
- The app uses `VStack(alignment: .leading, spacing: 0)` as the root layout, with manual spacing between sections

### Specific Spacing
| Context | Value |
|---|---|
| Header top padding | 8pt |
| Week strip top margin | 16pt |
| Divider below strip | 12pt top padding |
| Section spacing (detail view) | 32pt |
| Card internal padding | 16pt |
| Card corner radius | 14pt |
| Input field corner radius | 12pt |
| Habit row vertical padding | 16pt |
| FAB bottom margin | 32pt |
| Sheet horizontal padding | 24pt |
| Sheet top padding | 24pt |
| Calendar grid cell spacing | 3pt |
| Calendar cell corner radius | 3pt |

### Scroll Behavior
- Habit list: `ScrollView` + `LazyVStack(spacing: 0)` with `.scrollBounceBehavior(.basedOnSize)` — only bounces when content overflows
- Week strip: Horizontal `ScrollView` with `.scrollClipDisabled()` so scaled cells aren't clipped

---

## 5. Components

### 5.1 Header
- Left-aligned `VStack`: all-caps label ("OVERVIEW") → large date number (42pt bold) → weekday + optional "Today" pill
- Right side: progress ring + settings gear icon stacked vertically
- "Today" pill: white Capsule background, black text (11pt semibold), appears with `.opacity.combined(with: .scale(scale: 0.8))` transition

### 5.2 Week Strip (Gaussian Scroll)
- Horizontal scroll of day cells (56pt wide, 84pt tall)
- `.scrollTargetBehavior(.viewAligned(limitBehavior: .never))` for natural momentum with snap
- `.visualEffect` applies a **gaussian bell curve** transform based on distance from screen center:
  - Scale: 0.50× (edges) → 1.5× (center)
  - Opacity: 0.25 (edges) → 1.0 (center)
  - Y offset: 3pt (edges) → 0pt (center)
  - Gaussian sigma: 2.0
- Each cell: weekday abbreviation (gray, 11pt) → day number (white, 22pt bold) → activity dot (white 14×2pt rounded rect, or clear if no activity)
- Anchor: `.bottom` for scale effect

### 5.3 Habit Row
- `HStack`: left side has name (20pt bold white) + streak line (flame icon + "X DAYS STREAK" in 11pt gray with kerning)
- Right side: circular toggle button (32pt diameter)
  - Unchecked: white ring at 25% opacity, empty center
  - Checked: solid white fill + black checkmark (14pt bold)
  - Tap animation: spring bounce to 1.3× then back to 1.0×
- Rows separated by `Divider` at 8% white opacity

### 5.4 Progress Ring
- 48×48pt `ZStack` of two circles
- Track: `Color.white.opacity(0.15)`, 4pt stroke
- Fill: `Color.white`, 4pt stroke, `.round` lineCap, trimmed to progress
- Center: "X/Y" text (13pt semibold white)
- Animated with `.easeInOut(duration: 0.4)`

### 5.5 Stat Cards (Detail View)
- Arranged in 2×2 grid with 16pt spacing
- Each card: all-caps title (10pt medium gray, kerning 1.2) → value (28pt bold white) → subtitle (12pt gray)
- Background: `Color.white.opacity(0.06)`, corner radius 14

### 5.6 Calendar Heatmap (Detail View)
- 7-column `LazyVGrid` with 3pt spacing
- Each cell: `RoundedRectangle(cornerRadius: 3)`, aspect ratio 1:1
- Completed: `Color.white` / Missed: `Color.white.opacity(0.08)`
- Legend below: small 10×10pt squares with 10pt gray labels

### 5.7 Floating Action Button
- Centered at bottom of screen
- 56×56pt circle with `Image(systemName: "plus")` (22pt medium white)
- `.glassEffect(.regular.interactive(), in: .circle)` — iOS 26 frosted glass material
- Subtle shadow: `Color.black.opacity(0.3), radius: 10, y: 5`

### 5.8 Settings Screen
- `.listStyle(.insetGrouped)` with `.scrollContentBackground(.hidden)` (hides default background)
- Row backgrounds: `Color.white.opacity(0.06)`
- Toggle tint: `.white`
- Section headers: all-caps, 11pt medium gray, kerning 1.2
- Footer text: 11pt gray

### 5.9 Sheets
- `.presentationDetents([.medium])` — half-height
- `.presentationDragIndicator(.visible)`
- Black background, toolbar with Cancel (white) / Save (white bold)
- `.toolbarColorScheme(.dark, for: .navigationBar)`

---

## 6. Dynamic Island & Live Activity

### Compact View
- Leading: segmented circle (16pt) — no text
- Trailing: empty

### Minimal View
- Segmented circle only (16pt)

### Expanded View
- Center region: "Orbit" label (13pt semibold mono) + counter "X/Y" (18pt bold mono)
- Bottom region: white-tinted `ProgressView` bar
- Horizontal padding: 4pt, bottom padding: 2pt

### Lock Screen Banner
- HStack: checkmark.circle.fill icon → "X of Y habits done" → "X/Y" counter
- Monospaced, white on black, 16pt padding

### Segmented Circle
- Canvas-drawn arc segments with consistent gaps
- Completed segments: `Color.white` / Incomplete: `Color.white.opacity(0.25)`
- Stroke width: 16% of diameter, `.round` lineCap
- Gap angle: 8° between segments (with arc inset to prevent round cap bleed)
- Starts from top (−90° rotation)

---

## 7. Animation & Interaction

| Interaction | Animation |
|---|---|
| Toggle habit completion | `.easeInOut(duration: 0.25)` for state + spring bounce (response 0.25, damping 0.5 → then response 0.3, damping 0.6) |
| Progress ring fill | `.easeInOut(duration: 0.4)` |
| "Today" pill appear/disappear | `.easeInOut(duration: 0.2)` with opacity + scale(0.8) |
| Navigate to today | `.easeInOut(duration: 0.25)` |
| Programmatic scroll | `.interactiveSpring(duration: 0.35)` |
| Week strip scroll | GPU-accelerated via `.visualEffect` — no explicit animation, driven by scroll position |

### Haptic Feedback
- Light impact (`UIImpactFeedbackGenerator(style: .light)`) on habit toggle
- Gated by UserDefaults `"hapticFeedbackEnabled"` read at tap time

---

## 8. Navigation Pattern

- Single `NavigationStack` at root
- Habit rows are `NavigationLink` to detail view
- Settings via `.navigationDestination(isPresented:)`
- Detail view toolbar: `Menu` with ellipsis.circle icon → "Edit Name" + "Delete Habit"
- Destructive actions use `.alert` (not `.confirmationDialog`)
- Edit name reuses the AddHabitSheet in edit mode

---

## 9. Dark Mode

The app is **always dark**. Every screen applies:
```swift
.preferredColorScheme(.dark)
```
Navigation bars use:
```swift
.toolbarColorScheme(.dark, for: .navigationBar)
```

There is no light mode. The entire interface assumes a black canvas.

---

## 10. Key Principles (TL;DR)

1. **Black and white only** — no accent colors, ever
2. **SF Mono everywhere** — monospaced is the brand
3. **Opacity for hierarchy** — 1.0, 0.25, 0.15, 0.08, 0.06 are the key stops
4. **All-caps + kerning for labels** — tracked-out uppercase for section headers and metadata
5. **24pt horizontal padding** — consistent on every screen
6. **Minimal chrome** — no borders, no heavy shadows, no gradients (except glass FAB)
7. **White fills for completion** — checkmarks, calendar tiles, progress arcs, segmented circles
8. **Spring animations for tactile feedback** — bouncy toggles, interactive springs for scroll
9. **Data-forward** — stats, streaks, percentages, and heatmaps are the content
10. **iOS-native patterns** — NavigationStack, sheets with detents, .glassEffect, .visualEffect, ActivityKit
