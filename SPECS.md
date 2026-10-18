# Specs

## Local installation — 2026-10-17

- App: `/Users/jediOne/Applications/copy-on-select/CopyOnSelect.app`.
- Bundle `CFBundleExecutable` and executable filename must both be `copy-on-select`, matching the embedded Info.plist. Signing must report `Info.plist entries`, not `Info.plist=not bound`.
- LaunchAgent executable: `/Users/jediOne/Applications/copy-on-select/CopyOnSelect.app/Contents/MacOS/copy-on-select`.
- Original certificate SHA-1: `050390D8565BE77F55FAB7558F43BBC5B7E1A3FC`.
- Current certificate SHA-256: `6361C461996B1181AE8790B9AB8E2E2F52790CA4997474A87AD056E0B1FBDC41`; expiry: 2046-10-12 18:56:20 UTC. Unrestricted login-keychain identity check lists it as valid on 2026-10-17.

## Copied confirmation — 2026-10-08 design, retained on 2026-10-17

- Joel requested the existing snackbar and text approximately four times bigger.
- Panel: 368 × 136 pt (previously 92 × 34).
- Font: system semibold, 48 pt (previously 12).
- Corner radius: 68 pt (previously 17), preserving pill proportions.
- Existing placement: bottom center of pointer’s display, 48 pt above visible-frame bottom.
- Existing timing: 0.85 s visible, 0.18 s fade.
- Nonactivating, mouse-transparent panel; opaque vertical blue gradient: top `#2D92FF`, bottom `#0064E6`; white text (3.15:1 minimum calculated contrast at 48 pt semibold).
- Historical October 8 installation notes used `/Applications/CopyOnSelect.app` and a trailing-space identity name. These are not current deployment values; use the verified local-installation section above and its certificate fingerprint.

- Owner-approved: 4× size and iMessage-style blue with white text.
- Requested appearance: visible but not harsh, with a vertical gradient. User confirmed functional behavior on 2026-10-17; no separate aesthetic redesign/approval was solicited during this repair.
