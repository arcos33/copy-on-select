# Troubleshooting

Any app that copies on selection needs macOS Accessibility, and macOS ties that
permission to the app's **code signature and install path**. Change either and
the grant is silently revoked. That is the one failure mode worth knowing about
here — everything below is about recognising it and fixing it quickly.

The common way to meet it is an upgrade: rebuilding produces a new binary
identity, so macOS drops the grant and the app goes quiet until you re-enable
it. Usually that is a single checkbox.

## The menu bar icon is ⚠ and nothing copies

⚠ means one thing: **the app has no Accessibility trust** (or its event tap
died). It is a *permission* problem, not a code problem — the app is telling
you it cannot see anything.

### First, the 30-second checks

```sh
# Is it running, and from where?
ps -o pid,command= -p "$(pgrep -f CopyOnSelect | head -1)"

# Is it signed with ITS OWN certificate? (must say copy-on-select-local)
# NOTE: -dvv, not -dv. One "v" does not print the Authority line and has
# fooled us twice into thinking the app was unsigned.
codesign -dvv ~/Applications/copy-on-select/CopyOnSelect.app 2>&1 | grep Authority
```

**Restart the process after any permission change.** A running process does not
pick up a newly granted permission — most "it still doesn't work" reports are
really "the old process is still running".

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

**Takeaway:** if the icon and `--check` both look healthy but copying still
does nothing, do not trust either signal — they can't see the daemon's actual
TCC state. Go straight to the foreground-run test in step 3 above to confirm
whether it's a permission problem before looking anywhere else.

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

**How this was diagnosed:** temporary file-based debug logging (not the
unified log — reading it via `log show` requires Full Disk Access for the
terminal, which this session didn't have) at `applicationDidFinishLaunching`,
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
> re-sign, or reinstall needed, since this permission is independent of code
> signature and install path.

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

Almost always, re-enabling the checkbox and restarting the process is enough.
This section is for the rarer case where the grant refuses to stick — which
happens when one install path has accumulated several different signing
identities, leaving stale permission records that shadow the new grant.

A reboot is **not** required (it was twice the wrong instinct when we hit this).
TCC records are keyed by path, so a path macOS has never seen gets a clean
record.

```sh
# 1. Stop everything
launchctl unload ~/Library/LaunchAgents/dev.copy-on-select.plist 2>/dev/null
pkill -f CopyOnSelect; sleep 1

# 2. Reinstall the bundle at a NEW path (any unused path works)
NEW="$HOME/Applications/copy-on-select/CopyOnSelect.app"
mkdir -p "$(dirname "$NEW")"
cp -R <old bundle> "$NEW"
codesign --force --deep --sign copy-on-select-local "$NEW"

# 3. Point the LaunchAgent at the new inner executable
#    ProgramArguments[0] = "$NEW/Contents/MacOS/CopyOnSelect"

# 4. Delete the old bundle so nobody grants permission to a corpse
rm -rf <old bundle>

# 5. Launch it once so macOS registers it
open "$NEW"
```

Then, in **System Settings → Privacy & Security → Accessibility**:

1. **Remove every stale row** with **–** — any entry pointing at a path that no
   longer exists. *This step matters:* the fresh path alone did not work until
   the stale rows were gone. macOS matched the old record first.
2. Add the new app: **+** → ⌘⇧G → the new folder → select `CopyOnSelect.app`
3. Toggle it **on**
4. **Restart the process** (`launchctl unload && load`) so it re-queries trust
5. Test: `pbpaste` before and after selecting text

Lighter things worth trying first, in order — they are cheap and sometimes
enough:

```sh
killall tccd                                   # restart the permission daemon
tccutil reset Accessibility dev.copy-on-select # wipe this app's TCC record
```

`tccutil` only works because the app is a **bundle**. It cannot target a bare
executable ("No such bundle identifier"), which is one of several reasons the
bundle format is mandatory here.

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
  hit-test elements. Without it, `Engine.start()` returns `false` and the tap
  is never created at all.
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
