# copy-on-select

Select text anywhere on macOS and it is on your clipboard. That is the whole app.

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

## Install

**Fastest — let your agent do it.** Paste this into Claude Code:

> Install copy-on-select by following https://github.com/USER/copy-on-select/blob/main/install.md

Two steps need a human regardless: creating the code-signing certificate and
granting Accessibility are both GUI actions. The agent will stop and tell you.

Manual install is in [`install.md`](install.md) as well — the same steps, written
so a person or an agent can follow them.

Verify any time:

```sh
copy-on-select --check
```

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
