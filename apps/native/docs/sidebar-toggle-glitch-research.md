# Settings sidebar toggle glitch (the `>>` chevron) — research and diagnosis

> ## RESOLVED — final solution (verified on-device)
>
> Two changes together fixed both the `>>` flash and the bad layout:
>
> 1. **Settings UI moved into a dedicated SwiftUI `Window` scene** (NOT a
>    `Settings` scene). A real window scene is the only host where SwiftUI fully
>    owns the window chrome like Apple's Landmarks sample: a true full-height
>    sidebar, the toggle tucked by the traffic lights, and no reserved dead
>    title-bar band. `Window(_:id:)` is single-instance, so reopening just fronts
>    it. `.restorationBehavior(.disabled)` stops the menu-bar app auto-restoring
>    Settings at launch. AppKit still drives *when* it opens (dock-visibility
>    activation policy) by posting `.openSettingsRequested` to
>    `SettingsSceneBridge`, which now runs `@Environment(\.openWindow)`'s
>    `openWindow(id:)` (the old bridge used `openSettings()`). `SettingsLink` in
>    `.commands` was replaced with a plain `Button` calling
>    `appDelegate.openSettings()`, since `SettingsLink` only opens a `Settings`
>    scene.
>
> 2. **The sidebar toggle was moved off the sidebar toolbar segment onto the
>    DETAIL toolbar.** This is the actual root cause of the `>>` (see below): the
>    automatic toggle lives in the *leading (sidebar)* toolbar segment, and while
>    the column animates to zero width that segment cannot fit the ~40pt toggle
>    for a frame or two, so AppKit paints that segment's overflow `>>` chevron at
>    the divider. Removing the automatic toggle (`.toolbar(removing: .sidebarToggle)`
>    applied **on the sidebar column view** — applying it on the outer split
>    chain leaves it in place and you get *two* toggles) and hosting our own
>    `ToolbarItem(placement: .navigation)` on the detail content leaves the
>    collapsing sidebar segment with no item to overflow. Bonus: the detail's
>    leading edge is exactly where the native reference shows the toggle.
>
> `SettingsWindowConfigurator` (a tiny `NSViewRepresentable` reaching `view.window`)
> hides the window title and makes the title bar transparent for the clean
> no-title full-height look.
>
> Implementation: `WolfWaveApp.swift` (Window scene + Cmd+, button),
> `SettingsSceneBridge.swift` (`openWindow`), `SettingsView.swift` (detail toggle
> + `.toolbar(removing:)` on the sidebar column + configurator),
> `SettingsSidebarView.swift` (native `List`/`Label` rows).
>
> ---
>
> ### Earlier attempts (kept for the record — none fully worked)
>
> - **Option A** (move into SwiftUI's `Settings { SettingsView() }` scene so
>   SwiftUI owns the `NSToolbar`): killed the floating reveal chevron and the
>   duplicate-toggle regression, but the `>>` flash **survived** — proving the
>   flash is not about which host owns the toolbar.
> - **Option B v1** (custom toggle at `.navigation` on the outer split chain +
>   `.toolbar(removing: .sidebarToggle)`): still flashed, because `.navigation`
>   on the split routes to the *sidebar* segment — the same segment that
>   overflows. Also produced the awkward floating-toggle gap.
> - **Instant collapse** (`Transaction.disablesAnimations`): did not help; AppKit
>   animates the split divider regardless.
> - **Hidden title for slack**: improved the look but did not fix the flash.
>
> The breakthrough was realizing the overflow is *per-segment*: it is the
> collapsing **sidebar** segment that can't fit its toggle, so the cure is to put
> the toggle in the **detail** segment instead.

---

> ⚠️ **Everything below this line is HISTORICAL CONTEXT from the investigation,
> superseded by the RESOLVED section above.** It documents the app *as it was*
> mid-investigation — a hand-rolled AppKit `NSWindow`/`NSHostingController` Settings
> window with an empty `NSToolbar` shell, and a ranked list of fix *options* that
> were still being weighed. None of that describes the shipped code. The app now
> uses a dedicated SwiftUI `Window` scene (`WolfWaveApp.body`), a native
> `NavigationSplitView` sidebar, `.toolbar(removing: .sidebarToggle)` on the
> sidebar column, and a custom toggle on the detail toolbar. Read the section
> below only for the diagnostic reasoning, not for the current architecture.

## Why Option B failed (the "two toggles" regression)

Option B added a custom `ToolbarItem` and called `.toolbar(removing: .sidebarToggle)`
to drop SwiftUI's automatic one. But `.toolbar(removing:)` operates on SwiftUI's
own toolbar content model; once SwiftUI has populated a **foreign `NSToolbar`** it
does not own (the hand-rolled one assigned in `AppDelegate+Windows`), the removal
does not reach the already-bound automatic toggle. Net result: the automatic
toggle stayed **and** the custom item was added — **two toggles** in the title
bar (the automatic one near the sidebar/detail separator, the custom one at the
leading edge). The `>>` overflow flash was unaffected because its cause (the
tracking-separator layout race in the foreign toolbar) is independent of which
toggle is present.

Takeaway: inside a hand-rolled `NSHostingController` window you cannot reliably
remove the automatic toggle, so the only way to guarantee exactly one toggle is
to let the automatic one stand (empty `.toolbar { }`). Killing the flash requires
Option A.

## Symptom

A `>>` (double-chevron) icon flashes on the **right** side of the Settings window
title bar when the user **opens or closes the sidebar**. It is a transient artifact
during the collapse / expand animation, not a static control.

## How the Settings window is actually built

This is the key context. The Settings UI is **not** a SwiftUI scene. It is a
hand-rolled AppKit `NSWindow` that hosts the SwiftUI view through an
`NSHostingController`.

- `WolfWaveApp.swift:35` — the SwiftUI `Settings { EmptyView() }` scene is
  intentionally empty. `Cmd+,` is re-routed through
  `CommandGroup(replacing: .appSettings)` to `appDelegate.openSettings()`
  (`WolfWaveApp.swift:52-57`).
- `AppDelegate+Windows.swift:21` `openSettings()` shows / creates the window.
- `AppDelegate+Windows.swift:284` `createSettingsWindow()` builds the window:
  - style `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`
  - `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`
  - an **empty manual `NSToolbar`** (`displayMode = .iconOnly`), `toolbarStyle = .unified`
    (`AppDelegate+Windows.swift:324-327`).
  - content is `NSHostingController(rootView: SettingsView())`.
- `SettingsView.swift:126` `NavigationSplitView { List(selection:) } detail: { ScrollView }`,
  with `.navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)`
  (`SettingsView.swift:144`), an **empty `.toolbar { }`** (`SettingsView.swift:192`),
  and `.navigationSplitViewStyle(.automatic)` (`SettingsView.swift:199`).

There is **no custom sidebar toggle anywhere** in the codebase. The toggle is the
one SwiftUI's `NavigationSplitView` injects automatically.

## Why the empty `.toolbar { }` + empty `NSToolbar` exist

The two empty-shell pieces are a deliberate workaround already in the tree
(`SettingsView.swift:188-192` and `AppDelegate+Windows.swift:320-327`). Without
them, SwiftUI on macOS 26 could not find a title-bar host for the automatic
sidebar toggle and fell back to a **floating reveal chevron in the detail pane**.
The empty `.toolbar { }` forces SwiftUI's toolbar host to bind to the window's
`NSToolbar` instead.

That workaround fixed the *static* fallback. It does **not** fix the *animated*
case, which is what the user still sees.

## Root cause

SwiftUI's `NavigationSplitView` toolbar machinery (the sidebar toggle item **plus
the sidebar tracking separator** that keeps title-bar content aligned with the
sidebar divider) is being hosted inside a **hand-rolled `NSToolbar` that SwiftUI
does not own**. SwiftUI owns this machinery cleanly only when the view lives in a
SwiftUI **scene** (`WindowGroup` / `Window` / `Settings`), where SwiftUI creates
and drives the `NSToolbar` itself.

Here the bridge is the fragile path:

1. `.navigationSplitViewStyle(.automatic)` lets SwiftUI animate the sidebar
   column open / closed.
2. During that animation the title-bar width available to the toolbar changes
   frame by frame, and the tracking separator's target x position is mid-flight.
3. AppKit's `NSToolbar` recomputes item fit every frame. For one or two frames the
   computed content width exceeds the available width, so AppKit paints its
   **trailing overflow / clip indicator** — the `>>` double-chevron on the right.
4. When the animation settles, the items fit again and the chevron disappears.

So the `>>` is almost certainly the standard **`NSToolbar` overflow (clipped-items)
indicator**, which always renders at the trailing (right) edge. That matches both
"on the right" and "only while opening / closing." A secondary candidate is the
NavigationSplitView reveal chevron briefly appearing before the title-bar toggle
takes over; either way the underlying cause is identical: the split-view toolbar
items are not synchronized with the sidebar animation because they live in a
foreign `NSToolbar`.

This is consistent with the macOS skill's documented "NSHostingView animation
issues" guidance (frame / layout changes across the hosting bridge are not smooth;
prefer SwiftUI-owned windows for animated chrome).

## What is *not* the cause

- Not the `.transaction { $0.disablesAnimations = true }` on the detail
  (`SettingsView.swift:156`) — that only suppresses animation on **section
  change**, not on sidebar collapse.
- Not the column-width clamp (220-280) by itself — the overflow is a transient
  layout race during animation, not a steady-state width problem.
- Not a missing entitlement or a Music-bridge issue. Pure UI / toolbar layout.

## Fix options (ranked)

### Option A — Let SwiftUI own the window (robust, larger change)
Move the Settings UI into a real SwiftUI scene (`Window("Settings", id: ...)` or a
non-empty `Settings { SettingsView() }`) so SwiftUI creates and drives the
`NSToolbar`. The toggle, tracking separator, and overflow math then animate as one
unit and the flash goes away at the source.

- Pro: fixes the class of bug, not just this instance. Future-proof on macOS 26+.
- Con: the window is hand-rolled **on purpose** for dock-visibility modes
  (`menuOnly` / `dockOnly` / `both`), deferred show, miniaturize handling, and
  single-instance reuse (`AppDelegate+Windows.swift`). All of that would need to be
  re-plumbed onto a SwiftUI-scene lifecycle (`openWindow`, activation policy,
  `windowWillClose`). Medium-to-high effort and risk.

### Option B — Replace the automatic toggle with an explicit one (surgical)
Keep the hand-rolled window. Bind a `@State NavigationSplitViewVisibility` to the
split view, remove SwiftUI's automatic toggle with `.toolbar(removing: .sidebarToggle)`,
and add our own `ToolbarItem(placement: .navigation)` button that toggles the
binding inside `withAnimation`. A stable, app-provided item set gives AppKit
deterministic toolbar content, which should stop the transient overflow.

- Pro: small, localized to `SettingsView.swift`. Keeps the AppKit window
  architecture intact.
- Con: the tracking separator is still SwiftUI-managed, so this needs to be
  verified on-device; it may reduce but not fully kill the flash. Lowest risk to
  ship and easy to revert.

### Option C — Suppress / tame the toolbar overflow on the NSWindow side
Tune the manual `NSToolbar` (for example assert a non-overflowing item set, adjust
`displayMode` / centered items) so the clip indicator never paints.

- Pro: no SwiftUI changes.
- Con: `NSToolbar` has no first-class "never show overflow" switch; this is the
  most hack-prone option and the least likely to be clean. Not recommended as the
  primary fix.

## Recommendation

Start with **Option B** (surgical, low risk, reversible) and verify on-device. If
the flash persists because of the tracking separator, escalate to **Option A**.

## Verification plan

Building in this worktree needs `apps/native/WolfWave/Config.xcconfig`, which is
gitignored and must be copied from the primary checkout first (see CLAUDE.md). The
glitch is a 1-2 frame animation artifact, so verify by **eye on-device**: open
Settings, toggle the sidebar several times, watch the right edge of the title bar.
A screen recording stepped frame by frame is the most reliable confirmation.

## References

- Code: `apps/native/WolfWave/Views/SettingsView.swift`,
  `apps/native/WolfWave/Core/AppDelegate+Windows.swift`,
  `apps/native/WolfWave/WolfWaveApp.swift`.
- Skills consulted: `macos` (ui-review-tahoe/swiftui-macos, ui-review-tahoe/appkit-modern,
  appkit-swiftui-bridge/hosting-controllers), `swift`, `design` (liquid-glass).
- Relevant APIs (macOS 26 target, all available): `NavigationSplitViewVisibility`,
  `NavigationSplitView(columnVisibility:)`, `View.toolbar(removing: .sidebarToggle)`,
  `Window(_:id:)` scene, `NSToolbar` overflow behavior.
