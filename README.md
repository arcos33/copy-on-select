# copy-on-select

## Pick up here

**Last updated:** 2026-10-17

### Done
- Installed corrected bundle at `~/Applications/copy-on-select/CopyOnSelect.app`, retaining the original signing certificate. Executable and embedded metadata agree; strict signature verification passes.
- Re-granted Accessibility and Input Monitoring; daemon-attributed TCC logs allow both.
- Fixed Chrome accessibility activation with `AXEnhancedUserInterface` when `AXManualAccessibility` is unsupported. User's latest selection produced `selection found`, `commit scheduled`, and `show toast` in the trace.
- Added opt-in diagnostics without text/clipboard contents. Disabled temporary LaunchAgent debug settings after verification.
- User confirmed CopyOnSelect is working after the Chrome activation fix.
- Added the agent maintenance runbook below to preserve the working installation and diagnose future failures in order.
- Audited original setup notes and the complete repair session; reconciled current/historical guidance across the README, install/troubleshooting guides and project handoff files. Documentation-only follow-up; working app left unchanged.

### Next
- None. Repair and maintenance guidance are ready for normal use; use Git history and remote status to check publication state.

### Blocked
- None.

## Agent maintenance runbook — read before updating or troubleshooting

This installation was verified working by the user on **2026-10-17**, on macOS
27.2 (26B5101f). Preserve the working setup. The paths and certificate below
are specific to this Mac; on another machine, discover its existing setup
instead of copying these values. Read this section before following older
installation or troubleshooting notes, which include historical paths and
superseded diagnoses.

### Known-good installation

| Item | Verified value |
|---|---|
| App bundle | `/Users/jediOne/Applications/copy-on-select/CopyOnSelect.app` |
| Executable | `Contents/MacOS/copy-on-select` |
| Embedded and bundle `CFBundleExecutable` | `copy-on-select` — case matters |
| Bundle identifier / LaunchAgent label | `dev.copy-on-select` |
| LaunchAgent | `~/Library/LaunchAgents/dev.copy-on-select.plist` |
| Signing certificate | Existing `copy-on-select-local` identity |
| Certificate SHA-1 | `050390D8565BE77F55FAB7558F43BBC5B7E1A3FC` |
| Required permissions | Accessibility **and** Input Monitoring |
| Configuration | `~/Library/Application Support/copy-on-select/config.json` |
| Normal runtime | One process, started by the LaunchAgent; diagnostics disabled |

Do not change the install path, bundle identifier, certificate or user config
during a routine update. Do not create another certificate because
`security find-identity` reports no valid identities: an earlier restricted
check produced that result, while the current unrestricted check finds the
expected identity valid. This identity has successfully signed the app and
passed strict verification. Identify it by
the existing fingerprint; never substitute an ad-hoc signature or a different
certificate. Do not replace it with an unnotarized Developer ID build.

### Keychain: identity, trust and private-key access are separate

Do not diagnose all signing failures as a missing certificate. Check these
separately:

| Question | Evidence / action |
|---|---|
| Is this the intended certificate? | Match its fingerprint against the installed app's designated requirement, not just its display name. Multiple certificates can share a name. |
| Does the signing identity include an accessible private key? | A certificate lookup alone does not establish this. Inspect identities in the login keychain and test signing a staged app with the exact fingerprint. |
| Is Keychain access blocked or waiting for user interaction? | A signing operation may be waiting for the keychain-unlock or private-key access dialog. Inspect the prompt before retrying, replacing certificates or changing trust. |
| Does validation fail only in the agent sandbox? | Repeat the specific diagnostic in the appropriate unrestricted context. In this session restricted checks reported no valid identities, `Authority=(unavailable)` and `CSSMERR_TP_NOT_TRUSTED`, while unrestricted signing/verification succeeded. |
| Are existing app grants tied to this certificate? | Inspect daemon-attributed TCC results separately. Valid Keychain signing does not repair an Accessibility/Input Monitoring record bound to another certificate. |

**Current verified identity (2026-10-17):** login keychain, common name
`copy-on-select-local`, SHA-1
`050390D8565BE77F55FAB7558F43BBC5B7E1A3FC`, SHA-256
`6361C461996B1181AE8790B9AB8E2E2F52790CA4997474A87AD056E0B1FBDC41`.
Its expiry is **2046-10-12 18:56:20 UTC**. An unrestricted
`security find-identity -v -p codesigning` currently lists it as valid, and the
installed app passes strict verification. Historical notes about zero valid
identities, an untrusted certificate or a trailing-space name are not grounds
to change this working identity. Use the fingerprint to avoid name/whitespace
ambiguity. Other revoked/expired Apple Development identities appeared in the
keychain listing; they are unrelated to this app and must not be modified.

Read-only checks (certificate output is public certificate metadata, not the
private key):

```sh
security find-certificate -a -c copy-on-select-local -Z \
  /Users/jediOne/Library/Keychains/login.keychain-db
security find-identity -p codesigning \
  /Users/jediOne/Library/Keychains/login.keychain-db
security find-identity -v -p codesigning \
  /Users/jediOne/Library/Keychains/login.keychain-db
security find-certificate -c copy-on-select-local -p \
  /Users/jediOne/Library/Keychains/login.keychain-db \
  | /usr/bin/openssl x509 -noout -dates -subject -fingerprint -sha256
```

When signing a **staged** update, select the known identity explicitly:

```sh
# Replace this example with the validated staging path, never a guessed target.
codesign --force --deep \
  --sign 050390D8565BE77F55FAB7558F43BBC5B7E1A3FC \
  /path/to/staged/CopyOnSelect.app
codesign --verify --deep --strict /path/to/staged/CopyOnSelect.app
codesign -dvv -r- /path/to/staged/CopyOnSelect.app
```

If macOS asks to unlock the login keychain or authorize the private key, the
user enters their password directly into the system dialog. Never request,
capture or put that password in a command, environment variable or log.
For a prompt identifying Apple's `/usr/bin/codesign` and the intended key,
**Allow** authorizes the current request; **Always Allow** can avoid repeated
prompts for that tool. Private-key access approval is distinct from certificate
trust and from the app's two runtime permissions.

Do not use blanket fixes such as allowing every app to use the key, `security
import -A`, broad key partition-list changes, trusting all certificates,
resetting/deleting the login keychain or disabling system protections. Do not
change certificate trust merely to make a listing look clean. Diagnose the
specific error and preserve the working key and certificate. Stop before any
necessary credential replacement or trust-policy change and explain its effect
on this app's permission identity.

**New-machine/import recovery only:** restore the original certificate **and
private key** through a user-approved secure migration if available. A `.cer`
file alone cannot sign; generating another certificate with the same common
name does not preserve the original fingerprint or grants. If replacement is
unavoidable, document the new identity and plan fresh permission grants rather
than silently substituting it. Never export private keys as a diagnostic step.

The existing [certificate installation instructions](install.md#3-code-signing-certificate)
also record an import pitfall: Homebrew OpenSSL 3's PKCS#12 output can produce
`MAC verification failed ... (wrong password?)` with macOS's importer. Their
documented compatible path uses `/usr/bin/openssl`; check the tool versions and
format before assuming the password is wrong. This is background for a new
installation, **not a reason to regenerate this Mac's working identity**.
Keep private-key import access limited to `/usr/bin/codesign`, use protected
temporary storage, and remove temporary key/password files after an authorized
import. If a new certificate must be created, follow the full installation
instructions: Code Signing usage, a deliberate expiry, login keychain, and no
unnecessary personal email/address fields in the public certificate.

### Incident coverage and historical lessons

This runbook combines **observed October 17 failures**, **older recorded
incidents**, and **preventive advice**. They are not all new failures reproduced
in this session. Dated session/decision entries describe what was known at the
time; this checkpoint and the current installation specs describe today's state.

| Problem or trap | Evidence and durable lesson |
|---|---|
| Synced source mistaken for an updated app | October 14 session notes explicitly say repository sync did not deploy the app. Check source, installed bundle and running process independently. |
| Certificate lookup/trust false negatives | Restricted October 17 checks disagreed with successful unrestricted signing; older notes also recorded zero valid identities. Use the Keychain procedure above before concluding a key is missing. |
| Earlier certificate/import problems | Existing install instructions record the PKCS#12 format trap, key-access prompts and detailed Certificate Assistant settings. These are historical/new-machine guidance, not failures re-created in this repair. |
| Wrong identity persisted in permissions | October 17 ListenEvent logs named a different old certificate; a valid current signature and enabled Accessibility did not fix that other service's requirement. |
| Wrong app bundle metadata | Filename/embedded metadata mismatch left Info.plist unbound; the Settings picker failed to add the app until packaging was corrected. |
| Wrong permission target | A backup `.app` appeared as the granted entry. Archive/rename backup and staging bundles and select the exact live path. |
| Permission row missing after reset | Expected; add the corrected live bundle with + / ⌘⇧G, then enable it. Resetting a service revokes that grant until the user restores it. |
| Repeated reset/restart/path changes did not fix everything | Accessibility recovery alone did not resolve stale Input Monitoring or Chrome activation. Diagnose each stage before repeating a user action. |
| Two running copies | Manual launch and Quit & Reopen produced duplicates alongside launchd. Verify one exact executable process after these actions. |
| Installed agent mistaken for a running app | Initial LaunchAgent state was stopped. `--check` confirms the plist exists, not that launchd is running the correct process. This plist's KeepAlive only restarts unsuccessful exits; a deliberate successful Quit need not restart it. Inspect `launchctl print` rather than relying on presence at login. |
| Event tap creation mistaken for delivery | Older incident: tap creation succeeded but callbacks did not arrive without Input Monitoring. Check tap activity and actual events. |
| Old Chrome role-gating bug | Earlier repair added AXScrollArea/AXGroup to `leafTextRoles`; preserve it. It is distinct from October 17's missing web tree/activation issue. |
| Current Chrome activation bug | Manual activation was unsupported; enhanced activation exposed text after a delay. Preserve both the fallback and the earlier role-gating fix. |
| Screen Sharing has no local text selection | Observed gestures targeted Screen Sharing containers with no selection. Local text is the baseline; remote-display content needs its own supported workflow. |
| Missing snackbar confused with missing copy | Ask whether fresh selected text pastes without ⌘C. Trace selection → commit → toast before adjusting appearance. |
| Historical toast-design iterations | Size increased to 368 × 136 pt / 48 pt text; teal and charcoal were rejected, blue approved, then gradient requested. Preserve current dimensions, timing and colors; don't repeat those design changes while debugging copying. |
| Bare executable installation | Older notes document picker/reset difficulties. Keep the real app bundle rather than reverting to a loose binary. |
| Logout/reboot/cache theories | Older logs say logout/login and bootstrap-domain changes did not fix their event-delivery problem. Do not recommend them before checking the independently required permission. |
| Background-item notifications | Older notes describe these as informational. Do not change signing identity solely to remove a notification. |
| Premature success reports | A build, grant, active tap or toast call is partial evidence. October 17 ended only after the user confirmed working behavior. |

### Agent tools and execution context

- The initial Swift build failed with `sandbox-exec: sandbox_apply: Operation
  not permitted`; it succeeded outside the agent sandbox. That was an
  execution restriction, not an invalid Package.swift. Use the host's supported
  approval route for the specific command rather than changing project code.
- Restricted `pgrep` could not access the process list, and signature/Keychain
  results were misleading. Record diagnostic context and distinguish tool
  failure from app failure. An absent result is not proof an app/key is absent.
- `log show` without `--info --debug` missed useful TCC evidence. Short time
  windows also returned nothing when the failed action occurred earlier.
  Match the event's time and request IDs; widen only as needed. One attempted
  predicate (`messageType != activityCreateEvent`) was invalid: use the
  working subsystem predicate below rather than copying that expression.
- Older notes say their terminal could not read useful unified logs; this
  session could. Availability depends on execution context and settings.
  Empty logs are not proof of a healthy daemon, nor automatic justification
  for requesting Full Disk Access. Use opt-in non-content tracing if needed.
- App UI inspection of CopyOnSelect timed out; Chrome Computer Use was not
  approved. UI automation failure did not establish an app failure. Respect
  tool boundaries and use the app's own diagnostics or a focused user action;
  do not bypass a denied browser control surface through another mechanism.
- The user was in **Codex CLI**, not the desktop app. Desktop permission-menu
  instructions were initially wrong for that surface. In this session the
  user selected Full access via `/permissions`, removing routine command
  approvals. Verify the actual interface before giving settings instructions;
  agent execution permissions, Keychain access and app runtime grants remain
  different controls. Do not change global permissions on the user's behalf
  merely to troubleshoot this app.
- Do not leave the user waiting through repeated long diagnostics. Explain
  the current evidence briefly, run a focused check, and avoid asking for a
  selection again unless a fresh trace requires it. A user saying “done” means
  read the trace; it is not by itself confirmation that copying succeeded.

### Safe update procedure

1. **Check source and deployment separately.** Fetch the remote and inspect
   local changes/ahead/behind state. A synced Git repo says nothing about the
   installed or running app. Preserve local fixes, especially the Chrome
   activation fallback. Do not pull over changes, replace the working app, or
   commit/push merely to inspect sync status.
2. **Inspect the current deployment first.** Read the LaunchAgent, actual
   process paths, bundle Info.plist and designated signing requirement. Record
   the working state before changing it. A modification time or unequal binary
   hash alone does not establish which source revision built an app.
3. **Back up without creating another discoverable app.** Use an archive or a
   backup directory ending in `.bundle-backup`, not another `.app` bundle.
   Preserve permissions and metadata. Keep a matching LaunchAgent backup when
   changing its configuration. Do not launch backups. During this repair,
   Settings displayed `pre-update-20261017.app` instead of the intended app.
4. **Build and stage before stopping the working app.** Run `swift build -c
   release`. Assemble the bundle with the executable still named
   `copy-on-select`; its filename, bundle Info.plist and embedded Info.plist
   must agree. Sign the staged bundle with the original certificate.
5. **Verify the staged bundle.** Require strict signature verification, the
   original designated requirement, and `Info.plist entries=...` in signing
   output. `Info.plist=not bound` was a packaging fault here: the executable had
   been renamed `CopyOnSelect` while its embedded metadata named
   `copy-on-select`. Correct packaging before attempting permission recovery.
6. **Install and restart once.** Stop the existing LaunchAgent before replacing
   its executable. Install at the existing path, preserving the verified
   signature. Compare the installed executable with the **signed staged**
   executable; signing changes bytes, so comparing it with an unsigned build
   is not a deployment-integrity check. Restart the LaunchAgent. On a
   bootout/bootstrap sequence, wait for teardown to finish; a transient
   bootstrap error 5 is not a reason to run the user agent as root.
7. **Verify the actual daemon and behavior.** Confirm exactly one process at
   the intended path, both permission grants, and an active event tap. Have
   the user select fresh text in Chrome or TextEdit without pressing ⌘C,
   observe the blue Copied snackbar, and paste with ⌘V. Build success, a loaded
   LaunchAgent, a toggle, or a toast function call alone is not user-visible
   acceptance. Record what was verified and what remains unverified.
8. **Finish cleanly.** Disable temporary diagnostics, remove temporary `.app`
   staging copies from discovery, update this checkpoint and the changelog,
   and explain whether changes are installed, committed and pushed. Those are
   three separate states. Do not restart/re-sign again after acceptance unless
   there is a concrete reason.

Useful read-only checks for this installation:

```sh
plutil -p /Users/jediOne/Library/LaunchAgents/dev.copy-on-select.plist
launchctl print "gui/$(id -u)/dev.copy-on-select"
ps -axo pid,ppid,comm | rg 'CopyOnSelect.app/Contents/MacOS/'
plutil -p /Users/jediOne/Applications/copy-on-select/CopyOnSelect.app/Contents/Info.plist
codesign -dvv -r- /Users/jediOne/Applications/copy-on-select/CopyOnSelect.app
codesign --verify --deep --strict /Users/jediOne/Applications/copy-on-select/CopyOnSelect.app
```

### Diagnose in order; don't repeat permission resets blindly

| Evidence | Next check or action |
|---|---|
| No snackbar | First establish whether selection copying works. A snackbar is only shown after an accepted selection/copy. |
| No running process, wrong path, or multiple processes | Fix process ownership/path first. Opening the app or accepting Quit & Reopen can create another copy alongside launchd. Stop only confirmed duplicate PIDs and retain the LaunchAgent process. |
| Menu says Accessibility not granted | Check the actual daemon's permission verdict and packaging/signature. The permission pane is labeled **Device Control and Data Access** on this macOS build. |
| Toggle enabled but permission rejected | Inspect the saved code requirement in TCC logs. A visible toggle can refer to an old identity or app copy. |
| Accessibility allowed but no mouse events | Check **Input Monitoring** (`kTCCServiceListenEvent`) separately. In this incident it expected old certificate `4d06244afa5834357a8e4cf3274b77e8e725cad7`, rejecting the current certificate. |
| Permissions pass and gestures arrive, but Chrome returns no selection | Check browser accessibility activation and the hit-tested roles, as described below. |
| Selection found but no copy/toast | Follow generation, exclusion, bounds and clipboard-yield decisions before changing behavior. Respect another app's legitimate copy. |
| Copy commit and toast invocation logged, but user still reports failure | Verify actual paste and visible display behavior; do not infer success from function invocation alone. |

**Do not treat shell-launched `--check` as the daemon's permission verdict.**
macOS can attribute a shell-launched check to its terminal. Here it reported
Accessibility denied while daemon-attributed TCC requests were explicitly
allowed. Prefer the running app's menu, its opt-in startup trace and
daemon-attributed TCC logs. Likewise, running checks inside an agent sandbox
produced misleading signature/trust results; inspect the real installed app
in the appropriate execution context before changing anything.
The diagnostic's terminal warning also checks for `TERM`; absence of that
variable is not proof of independent launchd attribution. Its LaunchAgent check
only establishes plist presence. Inspect the real process and service state.

For focused permission evidence, use the app identifier, actual PID and a
short time window. Retain enough surrounding log lines to associate a request
ID with its service and result; an unrelated `Allowed` message proves nothing.

```sh
/usr/bin/log show --last 3m --info --debug --style compact \
  --predicate 'subsystem == "com.apple.TCC" AND (eventMessage CONTAINS[c] "dev.copy-on-select" OR eventMessage CONTAINS[c] "CopyOnSelect")'
```

An Apple-anchor mismatch is not by itself a failure for this self-signed app.
Look for the actual saved requirement, its match result, and the final service
authorization. Avoid collecting broad system logs or clipboard contents.

If evidence establishes a stale grant, reset **only the affected service for
this bundle**, then let the user re-grant it. These are recovery actions, not
routine update steps:

```sh
# Run only the line justified by the diagnosis, not both automatically.
tccutil reset Accessibility dev.copy-on-select
tccutil reset ListenEvent dev.copy-on-select
```

After a reset the row may disappear. In the affected permission pane, the user
can click **+**, press **⌘⇧G**, enter the known-good app path above, click
**Open**, and enable the toggle. Restart the app after granting, and inspect
for a duplicate created by Quit & Reopen. Preserve the other working grant.
Never edit the TCC database directly or reset permissions for every app.

Moving to a fresh install path is a **last-resort recovery**, not a standard
fix: it requires updating the LaunchAgent, app registration and user grants.
Resolve invalid packaging or signature metadata before asking the user to add
the app repeatedly. Keep the current working path stable from now on.

If Settings still resolves the wrong copy after correcting packaging, inspect
LaunchServices registration before changing the path again. During this repair
`lsregister -dump` identified the intended live bundle, and targeted
`lsregister -f` refreshed it after packaging repair. This is evidence about app
discovery, not a runtime permission grant. Do not reset the entire registration
database or create another visible staging `.app` as a shortcut.

### Backups and rollback

Current backup inventory is in [PROJECT-STATE.md](PROJECT-STATE.md). Backups
from different repair stages may contain the original packaging fault or lack
the Chrome activation fix. A backup's existence alone does not establish that
it is a known-good rollback. Historical paths in October 8 notes were not found
in the October 17 inventory; verify availability before promising recovery.

For a necessary rollback, identify and verify the exact backup first, preserve
the current app and plist, stop only the managed app/confirmed duplicates, and
restore a complete verified bundle at the intended live path with the matching
LaunchAgent executable path. Recheck its designated requirement and metadata;
do not blindly re-sign or delete the working copy. Start one process, verify
both grants and test a fresh selection. If rollback would change the signing
identity or undo the activation fix, explain that consequence before proceeding.

Use the dated [SESSION-LOG.md](SESSION-LOG.md) for incident chronology,
[DECISION-LOG.md](DECISION-LOG.md) for reasoning and [SPECS.md](SPECS.md) for
current deployment values. The new-install examples in [install.md](install.md)
must not override the working machine-specific setup above.

### Chrome-specific lesson: activate the web accessibility tree

The verified failure trace was:

```text
startup trusted=true started=true tapActive=true
selection gesture
target=com.google.Chrome excluded=false
manual accessibility result=-25205
leaf role=AXScrollArea
selection walk ... AXGroup
no accessible selection
```

`-25205` is attributeUnsupported: Chrome did not support the
`AXManualAccessibility` request used by the app. Its web-content tree was not
exposed, so walking native containers could not find selected text. Merely
increasing ancestor depth would not solve that missing tree.

`AX.enableManualAccessibilityIfNeeded` now falls back to
`AXEnhancedUserInterface` when manual activation is unsupported/not implemented.
Keep this fallback. Chromium handles that activation with a debounce of about
two seconds; request it **once per process**, not on every gesture, which can
continually postpone activation. The first gesture can activate the tree;
wait roughly three seconds and select another phrase for verification. In
this incident the enhanced setter returned `-25208`, but subsequent hit tests
changed to `AXStaticText`, and selection/commit/toast succeeded. Evaluate the
observed behavior rather than assuming the setter's return code tells the
whole story. See the [Chromium implementation](https://chromium.googlesource.com/chromium/src/+/HEAD/chrome/browser/chrome_browser_application_mac.mm).

Do not enable blind synthetic ⌘C as a workaround. Preserve secure-field checks,
gesture attribution, exclusions, size limits and clipboard-yield protections.
Screen Sharing can expose a remote desktop as an image/container rather than
local text; its gestures also produced no accessible selection in this trace.
Use local Chrome page text or TextEdit as the baseline, and check the actual
user config before testing a terminal/editor that may be excluded.

### Temporary diagnostics and completion criteria

`COPY_ON_SELECT_DEBUG=1` enables `DebugTrace` messages for startup, gestures,
selection decisions, commits and toast invocation. It does **not** log selected
text, clipboard data or mouse coordinates. To inspect the actual background
process, temporarily set that environment variable in **its LaunchAgent** and
capture stderr to a task-specific file; launching a second debug app from a
terminal can change permission attribution and create conflicting processes.
Back up the plist first, reload deliberately, and remove the debug environment
and stderr override afterward. Diagnostics are currently disabled.

Read evidence between attempts and make a specific change only when it
supports one. Ask for the smallest useful user action, such as selecting a
phrase, instead of repeatedly asking them to re-grant already-working access.
An agent's Full access mode reduces command approvals; it does not itself
grant the app macOS Accessibility or Input Monitoring permission.

**Done means:** the intended installed binary is signed correctly, one managed
process runs, both permissions pass for that process, fresh selected text
pastes correctly, the snackbar is visible, and the user confirms it works.

Select text anywhere on macOS and it is on your clipboard. That is the whole app.

A large, temporary **Copied** confirmation with white text on a blue gradient
appears after each successful copy.

You build it yourself from source you can read. It contains no networking code,
execs no subprocesses (no `Process`, no `posix_spawn`, no `NSAppleScript`), and
writes nothing to disk except the config file you ask it to create.

**Why build another one of these?** Because a tool that watches everything you
select needs the most invasive permission macOS grants, and every existing
option asks you to take its behaviour on faith. The closed-source ones (PopClip,
Keyboard Maestro) give you a binary and a privacy policy. The open-source ones
are better, but not actually verifiable: **you can read the source on GitHub and
still not know that the binary you downloaded was built from it.** Code
signing, notarization, and checksums all authenticate the publisher and the
bytes — none of them prove the bytes came from that source. Closing that gap
takes reproducible builds, which almost nobody offers, or compiling it yourself,
which is only meaningful if the code is small enough to actually read.

So this is small enough to actually read, has no network capability to begin
with, and you compile it yourself — which removes the gap rather than asking you
to trust across it.

---

## Install

**Homebrew:**

```sh
brew install yauyauyauhen/tap/copy-on-select
brew services start copy-on-select
```

This builds from source on your machine (that is the point). Then grant
Accessibility: System Settings → Privacy & Security → Accessibility → enable
`copy-on-select`. Note: upgrades produce a new binary, so macOS asks for the
Accessibility approval again after each `brew upgrade`.

**Or let your coding agent do it** (Claude Code, Codex, etc.) — paste this:

> Install copy-on-select by following https://github.com/yauyauyauhen/copy-on-select/blob/main/install.md

On this existing installation, preserve the existing signing certificate.
The user must approve any required Accessibility and Input Monitoring grants.

**Manual install** is in [`install.md`](install.md) as well — the same steps,
written so a person or an agent can follow them.

## Packaged alternative

[Pluks](https://pluks.app/) provides the same select-text-to-copy behavior as a
ready-to-install app.

Verify any time:

```sh
copy-on-select --check
```

If the menu bar icon shows ⚠ and nothing copies, see
the agent maintenance runbook above and [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).
Check both Accessibility and Input Monitoring before changing application code.

**Do not re-sign this app with another certificate.** macOS checks saved
permission requirements against the signing identity. Routine rebuilds must
retain the existing certificate and valid bundle metadata.

## Why this exists, and why it is built this way

I got the habit from Claude Code's TUI, which copies text as soon as you select
it. I liked it, and then it backfired: the reflex generalised. I started
selecting text in other apps and not pressing `⌘C`, assuming it was already
copied — and pasted and sent the wrong text more than once. A convenience that
works in only some apps trains a reflex that other apps do not honour, which is
worse than not having it.

So the goal is uniformity, not novelty.

The interesting part is not the feature. It is what you have to trust to run it.

### The problem with the alternatives

A tool that copies on selection needs macOS Accessibility, an unscoped,
all-or-nothing grant: any app holding it can read the UI of every running app and
synthesize input. That is unavoidable for this feature — including here. The
question is what else you are trusting.

- **PopClip / Keyboard Maestro** — closed source. Good reputations, but you are
  trusting a binary.
- **Hammerspoon** — open source (MIT), but a large Lua-embedding framework. You
  will not audit it, and the published binary is not reproducible, so you cannot
  confirm it matches the source on GitHub.

The usual answer is "contain it with an outbound firewall." That works, but note
what it costs: to police one small utility you install a system-wide traffic
inspector with far broader reach than the thing it contains. You traded a small
trusted surface for a bigger one.

### The argument this project is built on

Signing, notarization, and checksums authenticate the *publisher and the bytes*.
None of them prove the binary matches the published source — that requires
reproducible builds, or building it yourself.

So rather than proving code is benign, or containing it at runtime, prefer
**absence of capability**:

> A binary with no networking code cannot exfiltrate anything — not because
> something blocks it, but because the capability is not there.

That is checkable at the source level, by you, in a few minutes. It is why this
program is small and why you compile it yourself: you are the author of the trust
decision and the builder of the binary, so there is no gap between the two.

---

## Honest limits of that claim

Since the whole pitch is trustworthiness, here is where it stops:

1. **"No networking code" is a source-level property, not a kernel-enforced
   one.** Foundation is linked and could open a socket; a process-spawn could
   shell out to `curl`. Neither appears in this source — verify with:
   ```sh
   grep -rnE 'URLSession|NWConnection|CFStream|NSXPC|NSAppleScript|Process\(|socket\(' Sources/
   otool -L .build/release/copy-on-select   # system frameworks only
   ```
   A sandbox entitlement would be strictly stronger (kernel-enforced). App
   Sandbox is not currently compatible with the event tap this app needs; if
   that changes, it should be adopted.

2. **The clipboard itself is not private.** This app writes to
   `NSPasteboard.general`, which Handoff / Universal Clipboard may sync to your
   other Apple devices, and which every clipboard manager reads. Writing
   selections constantly *increases* what crosses that boundary.
   `markClipboardConcealed: true` marks writes `org.nspasteboard.ConcealedType`,
   which well-behaved clipboard managers and sync tools honour — but that is a
   convention, not a guarantee, and it is off by default so that clipboard
   history keeps working.
   **The accurate claim is: this tool adds no new exfiltration path of its own.**
   If your selections must never leave the machine, turn that key on and turn
   off Universal Clipboard.

3. **It still needs unscoped Accessibility.** No implementation can avoid that.

4. **You are still trusting the compiler and the OS.** Nobody closes that.

---

## How it works

macOS has no universal "selection changed" event. (An accessibility notification,
`kAXSelectedTextChangedNotification`, exists but coverage is app-dependent.)
Tools in this category therefore watch for the end of a mouse drag and fire `⌘C`.
Firing `⌘C` blind is what makes them misbehave: a drag in Finder copies *files*,
and a drag in a terminal running tmux copies whatever stale text was on the
clipboard.

This app **asks instead of guessing**:

1. Watch for a gesture that could change a selection — a drag, a double/triple
   click, or a shift-click (which extends a selection without moving the mouse).
2. Wait ~180 ms so the app has finished updating its accessibility state.
3. Ask accessibility for the element **that was actually clicked**, not the
   focused element — so the result belongs to this gesture, not to whatever is
   selected elsewhere.
4. If that element is a password field, stop. If it is not a text element at
   all — a Finder row, a canvas, a title bar, a scrollbar — **do nothing**.
5. Read the selection. If something else copied while we were resolving — a
   terminal with its own copy-on-select, say — leave its result alone.

The result: less coverage than a blind tool in apps with poor accessibility
support, in exchange for a much smaller chance of putting the wrong thing on
your clipboard. For an app whose entire reason for existing is a wrong-clipboard
bug, that is the right trade.

### It synthesizes ⌘C — read this

Accessibility answers *whether* something is selected far better than it answers
*what*. Measured across apps: Chrome and Linear return zero line breaks for a
bulleted list, and Notes returns no bullet characters at all, because list
markers are formatting rather than text.

So once accessibility has confirmed a safe selection, the app **synthesizes a
⌘C keystroke** and uses the app's own copy — which serialises lists, line breaks
and styling exactly as if you had pressed ⌘C yourself. That is the default
(`preferNativeCopyEverywhere`).

Know what this means before trusting it:

- **The mechanism is identical to pressing ⌘C yourself.** A web page's copy
  handler runs on your manual copies today; this fires the same event, just on
  every selection instead of every deliberate copy. No new mechanism — more
  occasions.
- **A correspondence check makes each copy stricter than a manual one**: the
  app's text is used only if everything accessibility saw appears in it, in
  order, with only bounded extras (list numbering). A page that appends or
  substitutes text fails the check and the clean accessibility text is written
  instead — which is better than a manual ⌘C, which would have kept the junk.
- The keystroke is **never sent** when accessibility reports a password field,
  when macOS secure input mode is active, or when the frontmost app is not the
  one the selection came from. In those cases — or if the copy produces
  nothing — the accessibility text is used, so it degrades rather than fails.
- Per-app opt-out: `nativeCopyDisabledApps`. Turning
  `preferNativeCopyEverywhere` off narrows it to the `preferNativeCopyApps`
  list (the apps where accessibility measurably loses structure).

The synthetic keystroke is never sent when accessibility reports a password
field, when macOS secure input mode is active, or when the frontmost app is not
the one the selection came from.

### Why there is an exclusion list

Some apps already do this, and doubling up is at best redundant and at worst
harmful:

- **Terminals and editors** — Claude Code's TUI already copies on selection, and
  captures mouse and clipboard handling itself. Terminals also run tmux and vim
  with mouse reporting, where a drag never produces a selection at all.
- **Finder** — a drag is a file drag.

Defaults are in `Config.swift` and can be overridden in your config file.

---

## Configuration

`~/Library/Application Support/copy-on-select/config.json`. The app reads this
file and never writes to it (use *Reveal Config…* in the menu bar to create a
default one).

| Key | Default | Meaning |
|---|---|---|
| `excludedBundleIDs` | Finder + several terminals | apps to ignore entirely |
| `settleMilliseconds` | `180` | delay before reading the selection |
| `maxCharacters` | `1000000` | ignore larger selections (`⌘A` in a big file) |
| `preferNativeCopyEverywhere` | `true` | use the app's own ⌘C everywhere (structure + styling) |
| `preferNativeCopyApps` | Chrome, Linear, Notes | the narrower list used when everywhere is off |
| `nativeCopyDisabledApps` | `[]` | apps where the native copy is never used |
| `yieldToExistingCopy` | `true` | don't overwrite a copy something else already made |
| `plainTextOnly` | `false` | drop styling from a native copy; structure survives either way |
| `enableCopyFallback` | `false` | last resort: ⌘C when accessibility finds *no* selection |
| `requireGestureNearSelection` | `true` | gesture must touch the selection's screen rect (blocks stale re-copies) |
| `dragThreshold` | `4.0` | points of movement that count as a drag |
| `maxAncestorWalk` | `5` | how far up the AX tree to look for the selection |
| `markClipboardConcealed` | `false` | hide writes from clipboard managers and sync |

`copy-on-select --apps` prints every running app with its bundle identifier, for
filling in the list keys.

Unknown or missing keys fall back to defaults, so a config written against an
older version keeps working.

---

## Status

Early. Built and compiling; the accessibility-dependent behaviour needs real
use across many apps before I would call it done. See the test matrix in the
project notes.

## License

MIT.
