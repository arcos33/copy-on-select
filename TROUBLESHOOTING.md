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

## Only ONE permission is needed

**Accessibility.** Nothing else.

If macOS offers **Input Monitoring**, decline it. The event tap listens to
left-mouse-down/up only; keyboard events are deliberately not tapped (modifier
state is read on demand via `CGEventSource.flagsState`). macOS offers that row
to anything creating an event tap, but this app does not need it and should not
have it.

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
