# Changelog

## 2026-10-17

- Prepared the user-verified repair and audited documentation for user-authorized commit and push; refreshed current handoff publication guidance.
- Audited original setup history and the full repair session for documentation coverage. Added incident/tool/rollback guidance, corrected misleading installer verification and broad recovery recipes, and refreshed PROJECT-STATE, ACTION-ITEMS, SPECS and SESSION-LOG. Historical pending states below describe intermediate steps; the final status is user-confirmed working behavior.
- Expanded README Keychain guidance: verified active identity/expiry, fingerprint selection, sandbox-related false negatives, private-key authorization versus certificate trust/TCC, unrelated expired identities, safe migration/import and prohibited blanket workarounds. Clarified current unrestricted check reports one valid local signing identity.
- Added a README agent maintenance runbook covering known-good paths/signing, safe deployment, packaging verification, permission attribution and scoped recovery, duplicate processes/backups, Chrome activation, diagnostic hygiene and user-confirmed acceptance. Corrected conflicting introductory troubleshooting/signing guidance.
- User confirmed CopyOnSelect is working after the packaging, permission and Chrome accessibility activation fixes.
- Verified user's Chrome selection reaches selection resolution, copy commit, and toast invocation after activation fallback. Disabled temporary debug environment/stderr capture.
- Chrome trace showed `AXManualAccessibility` unsupported and no readable selection. Added Chromium's `AXEnhancedUserInterface` activation fallback, once per process to avoid resetting its activation debounce; rebuilt, signed with original identity and restarted. Awaiting selection/snackbar verification.
- Added opt-in diagnostics for startup health, selection resolution outcomes and toast calls, without recording text or coordinates. Diagnostic release builds and verifies; launchd-started process reports trusted/started/tapActive all true and receives mouse-down callbacks. Corrected install instructions to preserve embedded executable name.
- After user re-granted Input Monitoring, verified daemon-attributed TCC logs allow both Accessibility and ListenEvent. Removed extra process spawned by Quit & Reopen; one LaunchAgent process remains. Real selection/snackbar test pending.
- Confirmed in TCC logs that Accessibility is granted. Input Monitoring rejects the current app against an older certificate requirement; reset only ListenEvent, terminated the extra app process and restarted the LaunchAgent. User must re-enable Input Monitoring.
- Repaired bundle executable-name mismatch against embedded metadata: installed executable and CFBundleExecutable now both use `copy-on-select`. Re-signed with original certificate; strict verification passes and Info.plist is now bound. Updated LaunchAgent and refreshed app registration; permission grant and real selection test remain pending.
- After permission reset failed to restore copying, moved the app to `~/Applications/copy-on-select/CopyOnSelect.app`, updated the LaunchAgent and restarted it. Original signature retained and verified; user must replace the stale permission row with the new path.
- Rebuilt synced commit `dff0489`, installed and restarted `~/Applications/CopyOnSelect.app` using its original signing certificate. Strict signature verification and staged/installed binary comparison passed; Accessibility permission remains pending.
- Preserved the prior app at `~/Library/Application Support/copy-on-select/backups/pre-update-20261017.app`.

## 2026-10-08

- Enlarged the Copied snackbar from 92 × 34 to 368 × 136 pt and its text from 12 to 48 pt; scaled corner radius proportionally.
- Installed signed release and restarted the existing LaunchAgent.
- Replaced translucent HUD background with opaque muted teal and white text for consistent contrast over other windows.
- Replaced rejected teal with charcoal `#333333` and soft white `#F5F5F5`; preserved accepted size and timing.
- Switched to requested iMessage-style blue `#007AFF` with white text after charcoal was judged too dark.
- Added a vertical blue gradient, lighter at top and deeper at bottom, to the accepted large blue snackbar.
