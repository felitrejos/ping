# Ping TODO

## Localization (ca + es)

Ship user-facing strings in Catalan and Spanish. The target audience is FGC riders in
the Barcelona area — English-only copy reads as tourist polish.

- Audit every user-visible string across `iOS/`, `macOS/`, `Shared/Views/`, and
  `Widgets/`. Move them into an `Localizable.xcstrings` catalog (Xcode 15+ string
  catalogs, so we get compile-time checks + automatic extraction).
- Add `ca` and `es` language entries; seed translations.
- Don't forget: notification bodies (`NotificationScheduler`), widget/live activity
  labels (`Widgets/`), error strings, accessibility labels, action names on notification
  categories.
- Verify `Info.plist` has `CFBundleLocalizations` listing `en`, `ca`, `es` and the
  `CFBundleDevelopmentRegion` stays `en` (or switch to `ca` if that becomes the default).
- Sanity-check Dynamic Type + truncation at longer Spanish/Catalan word lengths —
  headers like "Next trains" → "Pròximes sortides" / "Próximas salidas" grow the
  string ~30 %.
