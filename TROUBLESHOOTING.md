# Troubleshooting

**Start with the current [README agent maintenance runbook](README.md#agent-maintenance-runbook--read-before-updating-or-troubleshooting).**
It records the October 17 verified installation, Keychain checks, packaging
repair, stale Input Monitoring requirement, Chrome activation fix and exact
diagnostic order. The September entries below preserve older incident history;
they are not all explanations for the same failure or steps to run blindly.

Both Accessibility and Input Monitoring are required. Signing identity/path
changes can invalidate saved grants; same-certificate updates with valid bundle
metadata need not revoke them. Valid permissions do not guarantee a browser
exposes its selected text. Check deployment, packaging, daemon-attributed
permission evidence, event delivery, selection resolution and copy/toast behavior
in that order. Avoid repeated resets or reinstalling an already working app.

## The menu bar icon is ⚠ and nothing copies

⚠ indicates unhealthy Accessibility/event-tap state. Read the menu status and
trace the daemon before inferring which permission or code path is responsible.

### First, the 30-second checks

```sh
# Is it running, and from where?
ps -axo pid,ppid,comm | rg 'CopyOnSelect.app/Contents/MacOS/'

# Is it signed with ITS OWN certificate? (must say copy-on-select-local)
# NOTE: -dvv, not -dv. One "v" does not print the Authority line and has
# fooled us twice into thinking the app was unsigned.
codesign -dvv ~/Applications/copy-on-select/CopyOnSelect.app 2>&1 | grep Authority
```

The app retries after an initial startup failure, but Input Monitoring changes
may require a restart. After a grant, restart deliberately if needed and check
for duplicate processes rather than assuming a toggle alone is sufficient.

---

## Root cause: macOS pins the grant to the code signature

The Accessibility grant is bound to the app's **code identity + path**. Change
either and macOS silently revokes it. So:

> **Never re-sign this app with any other certificate.**
> It has its own: `copy-on-select-local`, self-signed, valid to 2046, created
> once by the user. Every rebuild signs with that same identity, which is why
> rebuilds normally do *not* require re-granting anything.

Things that have broken it in practice:

| What happened | Result |
|---|---|
| Signed with an Apple **Developer ID** without notarizing | `spctl` reports `rejected — Unnotarized Developer ID`; Accessibility stops working. **Strictly worse than self-signed.** Developer ID only helps as sign **and** notarize. |
| Another tool's session re-signed the app with *its* certificate | Grant revoked instantly. |
| Repeated identity changes at the **same path** | TCC accumulates stale records; new grants get shadowed by old ones. Toggle looks correct, grants nothing. |

---

## Icon looks healthy, `--check` says granted, but nothing ever copies

**Historical September incident.** The following records the original
investigation. For current recovery use the README's scoped service reset,
confirmed process IDs and current path; do not copy the old broad `pkill`/load
sequence into a working deployment.

Seen 2026-09-15, right after a same-day rebuild (the toast-notification change).
The menu bar showed `⚠`, then flipped to the healthy `⧉` on its own (expected —
see the polling note above), and `--check` reported Accessibility as granted.
Despite that, selecting text anywhere — including native AppKit (TextEdit),
the most-verified path — never reached the clipboard.

**Root cause:** a stale TCC record at this install path, left over from the
day's earlier rebuilds (see "Root cause" above — repeated identity changes at
one path can leave a grant that the *toggle* reports as on but that TCC never
actually honours for the running process). `--check` cannot catch this: its
Accessibility check runs `AXIsProcessTrusted()` in the *terminal's* process,
not the target binary's, so it reports the terminal's own grant and looks fine
regardless of the daemon's real state.

**How this was actually diagnosed** — by ruling things out in order:

1. Confirmed the failure wasn't app-specific: it failed identically in Chrome
   and in TextEdit (native AppKit, zero AX ambiguity).
2. Confirmed the running process was current: matched the installed binary's
   `codesign` identity, LaunchAgent path, and mtime against the latest build.
3. Ran the same binary in the **foreground** from a Terminal that already held
   Accessibility trust. Copying **worked** there. That isolated the problem to
   *this specific process's* grant, not the code.
4. `tccutil reset Accessibility dev.copy-on-select`, restarted via
   `launchctl unload`/`load` so the process re-registers and re-prompts,
   re-enabled the checkbox in System Settings. Copying worked again after that.

**Fix:**

```sh
launchctl unload ~/Library/LaunchAgents/dev.copy-on-select.plist 2>/dev/null
pkill -f CopyOnSelect
tccutil reset Accessibility dev.copy-on-select
launchctl load ~/Library/LaunchAgents/dev.copy-on-select.plist
```

Then re-enable **CopyOnSelect** in **System Settings → Privacy & Security →
Accessibility** (it will likely show as off, or drop off the list) and restart
the process once more so it picks up the fresh grant.

**Current takeaway:** a terminal-launched `--check` can reflect the responsible
terminal's grant in either direction. Prefer actual daemon-attributed TCC logs
and opt-in tracing. The foreground comparison above is historical evidence,
not today's default diagnostic: it can change attribution and create duplicates.

---

## Event tap silently stops delivering events (icon looks healthy, or flaps between healthy and missing)

Seen 2026-09-15, during the same-day churn that produced the stale-TCC finding
above. After several `tccutil reset` + re-grant cycles and a reinstall at a new
path (`~/Applications/copy-on-select/CopyOnSelect.app`), two new symptoms
appeared and **persisted across a full logout/login**:

1. The menu bar icon intermittently stopped rendering at all, even though
   in-process `NSStatusItem.isVisible` reported `true`.
2. `engine.start()` returned `true` (tap created) and `AXIsProcessTrusted()`
   was `true`, but `CGEvent.tapIsEnabled` reported `false` immediately, and
   **zero** mouse-down/up events ever reached `Engine.handle`. Selecting text
   produced no copy and no event at all — a fully "healthy-looking" daemon
   that had gone deaf.

**Ruled out first:** the WindowServer/login-session-cache theory (that
`tccutil reset` desyncs a per-session cache that only a logout/login clears).
A fresh login session showed the identical symptoms — `isTapActive=false`
immediately after tap creation — which is inconsistent with a stale *session*
cache. Also ruled out: launchd loading the job into the wrong bootstrap
domain — re-bootstrapping explicitly into `gui/<uid>` (`launchctl bootstrap
gui/$(id -u) ~/Library/LaunchAgents/dev.copy-on-select.plist` instead of the
legacy `launchctl load`) made no difference either.

**Root cause:** **Input Monitoring** (`kTCCServiceListenEvent`) was listed for
the app in **System Settings → Privacy & Security → Input Monitoring** but
toggled **off** — see the corrected section above. This is a separate
permission from Accessibility and gates event-tap *delivery*, not tap
*creation*. `AXIsProcessTrusted()`, `engine.start()`, and even
`CGEvent.tapCreate` itself can all report success without it; only
`CGEvent.tapIsEnabled` and the actual absence of callbacks give it away.

**How this was diagnosed:** temporary file-based debug logging (that session
could not access useful unified logs; availability differs by execution context,
and October 17 successfully used focused `log show --info --debug`) at `applicationDidFinishLaunching`,
`Engine.handle`, and `MenuBar.updateButton`, showing `isTapActive=false`
immediately after a `true` return from `engine.start()`, with no `handle:`
lines ever appearing regardless of selections made. That combination —
creation succeeding, activity flag false, zero callback log lines — is the
fingerprint of a missing Input Monitoring grant rather than an Accessibility
or WindowServer problem.

**Fix:**

> **System Settings → Privacy & Security → Input Monitoring** → find
> **CopyOnSelect** → toggle **on**. macOS will ask you to quit and reopen the
> app; let it. Confirm with `pbpaste` after selecting text — no rebuild,
> re-sign, or reinstall needed merely to enable it. It is separate from
> Accessibility, but it also has saved code-identity requirements; October 17
> logs showed an old certificate requirement rejecting the updated app.

**Takeaway:** if the tap-health signals (`AXIsProcessTrusted`,
`engine.start()` return value) all say healthy but no events ever arrive,
don't keep chasing Accessibility or WindowServer/session state — check Input
Monitoring first. It fails silently and looks identical to a dead tap from the
outside.

---

## Chrome never copies, even though everything else (permissions, tap, TextEdit) is healthy

Seen 2026-09-15, found while re-verifying copy after the Input Monitoring fix
above. Every permission was granted, the event tap was firing, and TextEdit
copied correctly — but selecting text in Chrome produced nothing, silently,
with no error anywhere.

**Root cause:** a role-gating bug in `AX.findSelection` (`AX.swift`), not a
permission problem. `AXUIElementCopyElementAtPosition` frequently hit-tests a
Chrome page drag onto the outer `AXScrollArea`/`AXGroup` wrapping the page's
`AXWebArea`, rather than onto the web area or a text node directly. The code
only permits walking up to ancestors (`mayConsultAncestors`) when the *clicked
leaf's* role is in `leafTextRoles` — and neither `AXScrollArea` nor `AXGroup`
were in that set, even though both are already in `readableRoles` (the set
consulted once walking is allowed). So a depth-0 `AXScrollArea` hit had no
route to ever reach the ancestor `AXWebArea` that actually held the selection:
`findSelection` returned `.none` every time, indistinguishable from "nothing
was selected."

**How this was diagnosed:** temporary logging in `findSelection` of the leaf
role, `mayConsultAncestors`, and the role at each depth of the walk. It showed
`leafRole=AXScrollArea mayConsultAncestors=false`, with the walk staying on
`AXGroup` at every depth up to `maxAncestorWalk` and never encountering
`AXWebArea` — confirming the gate, not the walk depth or the hit-test itself,
was the blocker.

**Fix:** added `kAXScrollAreaRole` and `kAXGroupRole` to `leafTextRoles`
(`AX.swift:44`). These are generic containers, not interactive controls — the
ambiguity the `leafTextRoles` gate exists to prevent (picking up an unrelated
container's stale selection) is about controls like buttons and images,
already filtered earlier by `interactiveLeafRoles`. Restricting ancestor
lookups to a fixed leaf-role allowlist doesn't add real safety there; it just
breaks browsers whose hit test lands on a generic wrapper. `maxAncestorWalk`
(default `5`) was confirmed deep enough to reach `AXWebArea` from a typical
Chrome scroll-area hit — no change needed there.

**Takeaway:** if a specific app (especially a browser) never copies while
everything else works, suspect the role-gating logic before permissions —
temporarily logging the leaf role and the role at each ancestor-walk depth
will show immediately whether the walk is even being allowed to start.

---

## If a normal re-grant does not take: the recovery recipe

The old procedure here moved the app and deleted the prior bundle. Do not run
that as a first response. October 17 demonstrated that repeated Accessibility
resets/path changes did not address a separate stale ListenEvent requirement
or Chrome's unactivated web tree. Packaging first had to be repaired so the
Settings picker could accept the app.

1. Verify bundle metadata, original signing requirement and intended process.
2. Use TCC logs to identify the rejected service and requirement. If only
   ListenEvent is stale, preserve working Accessibility (and vice versa).
3. Reset only the diagnosed service for `dev.copy-on-select`, then ask the user
   to add/enable the exact current bundle in that service's pane.
4. Restart one LaunchAgent process, check callback/selection evidence and test
   fresh text without pressing ⌘C.
5. Only consider a fresh path if packaging and scoped recovery fail and
   evidence still points to the old registration/path. Preserve a recoverable
   backup and matching plist, update registration/LaunchAgent together, and
   retire only confirmed stale entries for this app. Do not delete a working
   bundle or reset unrelated applications' permissions.

The known-good path is already `~/Applications/copy-on-select/CopyOnSelect.app`;
do not select it as a supposedly unused recovery destination. Its executable
is `Contents/MacOS/copy-on-select`, not the old uppercase filename. A reboot,
logout, killing all permission daemons or changing to a root launch domain is
not the default recovery action. See README for scoped reset commands and
the user-facing add instructions.

---

## Why the app is a `.app` bundle, not a bare executable

A bare executable caused a full day of trouble:

- the Accessibility **+** picker refuses to show it (you must drag it in)
- `tccutil` cannot reset it — no bundle identifier
- its TCC records are fragile when the signing identity changes

A bundle is what macOS expects from anything requesting Accessibility. Do not
"simplify" the install back to a loose binary.

---

## Two permissions are needed: Accessibility AND Input Monitoring

**Corrected 2026-09-15** — this section previously said Input Monitoring
should be declined. That was wrong and cost a long debugging session; see
"Event tap silently stops delivering events" below for how this was found.

Both are required, and they gate different things:

- **Accessibility** (`AXIsProcessTrusted`) — required to read selections and
  hit-test elements. `Engine.start()` delegates to event-tap creation rather
  than explicitly checking this grant; a successful start alone does not
  establish accessible selection data.
- **Input Monitoring** (`kTCCServiceListenEvent`) — required for the event tap
  to actually *deliver* events, even though the tap only listens
  (`.listenOnly`) to left-mouse-down/up and never taps keyboard events.
  `CGEvent.tapCreate` can **succeed** without this grant — the mach port gets
  created and `engine.start()` returns `true` — but `CGEvent.tapIsEnabled`
  reports `false` and the callback never fires. This looks exactly like a
  healthy tap that has gone deaf, not like a missing permission.

If macOS offers the Input Monitoring row when the app first runs, **grant it**.
Declining it, or having it silently toggled off during TCC churn, produces the
symptom below.

---

## "App Background Activity" notifications

Informational, not a fault. Every newly registered background item is announced
once; re-registering (new path, new build) announces again. Self-signed items
may be re-announced more often since macOS cannot attribute them to a
registered developer.

The only structural cure is a Developer ID signature **plus notarization** —
and note that unnotarized Developer ID actively breaks Accessibility (above).
Notarizing the local build would work and would expose nothing publicly, but it
adds a several-minute notarization round-trip to *every* rebuild. Currently
judged not worth it.
