# Ping TODO

## Bugs

- [ ] **Header icon invisible in light mode** — `headerIcon` in `iOS/ContentView.swift` hard-codes `.foregroundStyle(Color.white)`, so the top-left logo disappears against the light-mode background. Use `.primary` (adapts automatically: black on light, white on dark) or `Color(uiColor: .label)` if more control is needed.

## Accessibility

- [ ] **Respect Reduce Motion** — the radial pulse on the nearby `StationMarker` (`iOS/FGCMapView.swift`) and the leave-now scale bump on `TrainHeroCard` (`iOS/ContentView.swift` → `LeaveNowBumpModifier`) should be gated behind `@Environment(\.accessibilityReduceMotion)`. Pulse: skip the animation entirely and render a static ring. Bump: fall back to a brief opacity flash or no effect. Haptics already respect system settings; only the visual motion needs wiring.

## Home page polish (pre-search screen)

Current layout: `pingHeader` → `routeSection` → `quickSwitchSection` → `searchRoutesButton` → `serviceAlertsSection` → `statusBanner` → `calendarSection`. Reads as a form. Some ideas, in order of bang-for-buck:

- [ ] **Next-departure preview card above the fold** — if the user has a saved default origin/destination (very common), show a small live countdown for their next catchable train right on the home screen, above `routeSection`. Skips the search step for the 80% case and makes the app feel alive the moment it opens. Tap → jumps to the results screen already populated. Biggest UX win on the home page.
- [ ] **Group origin/destination + swap into one card** — the three elements of `routeSection` currently float as plain rows. Wrapping them in a single rounded container (à la Airbnb search, or Apple Maps' origin/destination panel) makes the primary interaction obvious and visually separates it from the favorites row below. The swap button sits inside the card on the trailing edge.
- [ ] **Line-color dots on favorites** — in `quickSwitchSection`, each favorite capsule could show a small colored dot/badge for the FGC line the station belongs to (R1, R2, S1, etc. — the line colors are already a brand asset). Helps recognition at a glance and breaks up the uniform gray capsules.
- [ ] **Favorites empty state** — if `store.favoriteStations.isEmpty`, the whole `quickSwitchSection` currently vanishes. A brief "Star a station in the picker to add it here" hint would prevent the home page from feeling sparse on first launch.

## Explicitly dropped (history)

- ~~Noise texture on card backgrounds~~ — barely perceptible on device, didn't earn its complexity.
- ~~One-shot shimmer on live data refresh~~ — didn't land visually; the phase-driven countdown color already carries "fresh / on track / urgent."
- ~~Always-on shimmer loop~~ — decorative on a utilitarian card.
- ~~Flowing wave in timeline bars~~ — adds motion to the one strip that should stay stable and scannable.
- ~~Shader-driven breathing glow border~~ — the urgency signal is better carried by the phase-driven countdown color than a second animated element competing for attention.
- ~~"Switch to next train" actionable notification~~ — tapping a notification action silently in the background gives no feedback about the new train (time, line, walk). Default tap already opens the app, which is what users need anyway. Not worth the `UNNotificationAction` + background handler complexity.
