# Decision Log

## 2026-10-18 — One Paste action with explicit release

Joel approved hold/slide/release and explicitly rejected a plain-text choice. Use left-button hold with a gap between the pointer and button so a stationary release cancels. The mouse-only tap is now an active tap: native down passes through, pre-hold drags remain ordinary, post-activation drag events are consumed, and the real up is delivered at the initial caret. This preserves the down/up pair without sending an extra synthetic click. Native Command-V is sent only after release and revalidation of the same focused field, insertion range, foreground process and clipboard generation. No clipboard rewriting or history is introduced.

Cancelled/stale copy work must not overwrite the clipboard while the paste gesture is active, so generation is checked at the actual copy commit as well as during resolution. The existing Chrome activation and role handling are retained. Apps excluded from copying remain excluded from hold-paste for this first release.

This Mac has Command Line Tools without XCTest; `swift test` failed with `no such module XCTest`. Use the checked-in standalone Swift test runner; it exercises cancellation, pointer jitter, drag-out-and-back, stale lookups, modifiers, single-shot paste and display-edge placement. The configured PiKVM tool supports continuous drag but not hold-then-slide; Joel performed the actual gesture check and confirmed success, cancellation, and automatic copying. Do not change PiKVM just to automate this check.

## 2026-10-18 — Version label and machine-specific deployment

Joel approved 1.1.0, treating the earlier app as 1.0.0. Read the menu version from bundle metadata. Synced October 17 installation notes describe the jediOne Mac, not the Mac mini: live LaunchAgent/signature inspection established /Applications/CopyOnSelect.app and DFB4CDB9E1186449F600B5DC796C5B89B03E0865 here. Preserve machine-specific identities; a zero-valid-identities listing did not prevent successful staged signing with this existing certificate and strict verification.

Entries below record decisions and evidence at their dates, including interim
uncertainty. For current verified status read README and PROJECT-STATE.md;
October 17 ended with user-confirmed working behavior.

## 2026-10-17 — Reconcile original setup history with the completed repair

Keep older evidence without presenting it as newly reproduced or current.
Document both Chrome fixes (role gating and activation), historical Keychain
import/trust issues, tool-context failures, and unsuccessful recovery attempts.
Correct actionable contradictions in install/troubleshooting guidance and stale
handoff files so agents preserve the working path/identity and diagnose using
actual process evidence. Remove the old destructive path-recovery template;
explain recoverable rollback and known backup limitations instead.

## 2026-10-17 — Correct Keychain diagnosis using current evidence

An unrestricted login-keychain check now lists fingerprint `050390D8565BE77F55FAB7558F43BBC5B7E1A3FC` as valid; installed signature verification passes. The certificate expires 2046-10-12 18:56:20 UTC. Earlier zero-identity/untrusted outputs must not be treated as proof this key is absent or needs replacement. README now separates identity/private-key availability, user key-access authorization, trust validation and TCC's saved requirements; records exact fingerprint and discourages broad trust/ACL changes. No Keychain settings were changed for this documentation update.

## 2026-10-17 — Preserve operational lessons in the README

Put the verified maintenance procedure near the top so future agents read it before older installation/recovery notes. Separate source sync from deployment, require packaging/signature checks before permission churn, and use daemon-attributed evidence and user acceptance as completion criteria. Document the known-good local setup and narrow service-specific recovery without turning disruptive resets or path changes into routine update steps.

## 2026-10-17 — Activate Chrome's web accessibility tree

Live trace confirms healthy permissions/event tap, Chrome selection gestures, `AXManualAccessibility` returning attributeUnsupported (-25205), and a hit-test chain containing only AXScrollArea/AXGroup. Chromium's BrowserCrApplication implements `AXEnhancedUserInterface` with a two-second debounce (https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/chrome_browser_application_mac.mm). Use it when manual activation is unsupported, once per process. Retain existing selection validation and safe fallback behavior; don't send blind Cmd+C to work around the missing tree. Release build/signature verification passed; actual user selection remains the acceptance test.

## 2026-10-17 — Confirm permission attribution in TCC logs

The shell-launched `--check` reported Accessibility denied even while the daemon's TCC requests were explicitly allowed. Use daemon-attributed logs or its menu for permission diagnosis. Logs identify the actual remaining blocker as ListenEvent code-requirement mismatch against old leaf certificate `4d06244afa5834357a8e4cf3274b77e8e725cad7`. Current app retains `050390d8565be77f55fab7558f43bbc5b7e1a3fc`; reset only ListenEvent, preserve Accessibility, and await user's new Input Monitoring grant. Removed duplicate running process to leave launchd as the sole launcher.

## 2026-10-17 — Align bundle executable metadata

After the Settings picker failed to add the app, inspected embedded metadata and found `copy-on-select` while the bundle executable was renamed `CopyOnSelect`. Corrected packaging to match the embedded name and retained the original certificate. Signing output changed from `Info.plist=not bound` to `Info.plist entries=8`. This verifies the packaging repair; whether it resolves the permission picker still requires user confirmation. Backups and staging copies now use `.bundle-backup` rather than `.app` to avoid competing app registrations.

## 2026-10-08 — Scale existing confirmation

Interpret 4× as four times the linear dimensions and font size. Preserve position, timing, appearance and copy behavior. Keep the installed version’s source baseline rather than bundling unrelated remote AX changes into this visual adjustment.

Preserved the original certificate and designated requirement. `security find-identity -v` lists no valid identities because the local self-signed certificate is not trusted; the matching identity remains available and successfully signs the app. Strict bundle signature verification passed. Do not replace the certificate to resolve that listing.

Backup: `~/Library/Application Support/copy-on-select/backups/20261008-222622/CopyOnSelect.app`.

## 2026-10-08 — Muted teal contrast

Joel accepted the size but found the background difficult to see. Use opaque muted teal `#245C5C` with white text: 7.61:1 calculated contrast independent of content behind the panel. Preserve accepted size and existing timing/placement. Backup before color change: `~/Library/Application Support/copy-on-select/backups/20261008-222925/CopyOnSelect.app`.

## 2026-10-08 — Neutral color revision

Joel disliked teal. Changed to opaque charcoal #333333 with soft white #F5F5F5 (11.59:1 contrast). This is a proposed neutral alternative, not yet visually accepted. Preserved 4× size and timing. Pre-revision backup: `~/Library/Application Support/copy-on-select/backups/20261008-223206/CopyOnSelect.app`.

## 2026-10-08 — Blue direction

Joel rejected charcoal as too dark and requested the familiar blue associated with iMessage. Use opaque #007AFF with white text, preserving accepted 4× sizing. Calculated contrast 4.02:1 for large semibold text. This is an iMessage-style choice, not a claim that all current Messages interfaces use one exact hex. Backup: `~/Library/Application Support/copy-on-select/backups/20261008-223342/CopyOnSelect.app`.

## 2026-10-08 — Blue gradient

Joel approved blue and requested an iMessage-like gradient. Use AppKit NSGradient in a background NSView, clipped by the existing rounded layer: #0064E6 bottom to #2D92FF top. White-text contrast remains at least 3.15:1 for the existing large semibold label. Preserve accepted dimensions and timing. Backup of approved flat-blue app: `~/Library/Application Support/copy-on-select/backups/20261008-223825/CopyOnSelect.app`.

## 2026-10-18 — Scope GitHub authentication to the repository owner

The initial push failed with HTTP 403 because the active gh account was hikarisushi. Retrieved the saved arcos33 token in memory, verified its identity through the GitHub API, and scoped GH_TOKEN plus the gh credential helper to the push subprocess. Push succeeded without changing the global active account or credentials. For future publication, verify the repository owner account rather than assuming the active business login has access.

## 2026-10-19 — Distinguish credential existence from execution-context access

Corrected the earlier inference that no arcos33 credential was available: metadata lookup confirmed the GitHub CLI item in the login Keychain. Orca-hosted Codex could not retrieve its secret; native-client comparison and token validity remain unverified. Exit 36 is consistent with interaction-not-allowed OSStatus, not conclusive proof of the cause. Diagnose execution context and metadata before searching for replacement tokens. Preserve global credentials and permissions. See TROUBLESHOOTING.md for evidence and the diagnostic order.
