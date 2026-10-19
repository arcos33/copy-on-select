# Specs

## Hold, slide, release to paste — 2026-10-18

- Joel approved a single **Paste** action; no plain-text choice and no automatic paste on a stationary hold.
- Hold the left mouse button still for 0.5 seconds in a supported editable field; slide onto Paste and release to paste once. Release outside to cancel.
- Moving more than 6 pt before activation cancels recognition for that gesture. Ordinary clicks, double-clicks, modified clicks, selection drags and existing exclusions retain their normal behavior.
- The 124 × 48 pt button appears 18 pt beside the press, flips left near a screen edge and stays in the visible display area. System light/dark colors, 17 pt semibold label, highlighted hover state. No clipboard preview, history or disk storage.
- Focus must match the hit-tested editable field; secure/read-only/unknown targets are skipped. Holding already-selected text remains a native text-drag gesture. Clipboard changes or a changed destination cancel the pending paste.
- Paste uses native Command-V with the existing clipboard formats. Pause disables observation and cancels pending actions. No keyboard events are monitored.
- Version remains the agreed feature release **1.1.0**, build **3**. CLI and menu read the same bundle version.
- Joel confirmed successful paste, release-outside cancellation, and unchanged automatic selection-copy with its blue Copied popup on 2026-10-18. Broader app/monitor coverage remains unverified.

## Version numbering — 2026-10-18

- Joel treats the existing app as 1.0.0 and approved 1.1.0 for this release. Version-label-only release used build 2; the accepted hold-paste release uses build 3.
- Menu begins with a disabled `CopyOnSelect v1.1.0` label, read from CFBundleShortVersionString rather than duplicated in code.

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
