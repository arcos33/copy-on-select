# Backlog

---

## ⚠️ TEMPORARY DEBUG STATE — clean this up before calling it done

Everything in this section is scaffolding, not the product. **Check this list
whenever debugging stops**, and delete the section once it is all reverted.

| State | Where | Action to revert |
|---|---|---|
| `enableCopyFallback: false` | `~/Library/Application Support/copy-on-select/config.json` | Decide the real default, then either delete the file or write the intended config. **This is a live deviation from the shipped default.** |
| Probe binaries + sources (`axprobe*`, `wkhelper*`, `upwalk`, `winlist`, `dump`, `probe4/5`) | session scratchpad under `/private/tmp/claude-501/…` | Delete. Session-isolated so harmless, but do not let any of it drift into the repo. |
| Diagnostic logging, if added | `diagnostics` config key + log calls | Must be **off by default**, and must never log selection content — only timings, roles, and lengths. Consider removing entirely before publishing. |
| Clipboard sentinels (`SENTINEL-…`) | the clipboard | Self-clearing; nothing to do. Just do not mistake one for real data. |
| `wkhelper` GUI windows | were left running by a review agent | Already killed (2026-07-25). Re-check with `ps aux \| grep -i wkhelper` if odd windows appear. |

Deliberately **not** temporary (leave these alone): the installed binary in
`~/Applications`, the LaunchAgent, the `copy-on-select-local` certificate, and
the Accessibility grant.


Things worth doing the next time this gets rebuilt. Nothing here is urgent —
the app works — so these are batched deliberately rather than triggering a
rebuild each on their own.

**Rebuild cost, for reference:** `swift build -c release` → `codesign` with
`copy-on-select-local` → copy to `~/Applications` → `launchctl unload/load`.
About 30 seconds. **The Accessibility grant survives**, because the stable
self-signed certificate keeps the binary's identity constant across rebuilds —
that is the whole reason for using a certificate instead of ad-hoc signing.

---

## Menu bar icon (batch these together)

The current icon is the Unicode glyph `⧉` set as `button.title`, which is why it
looks slightly off next to native menu bar items.

- [ ] **Increase size ~20%.** One line: `button.font = NSFont.systemFont(ofSize: 17)`
      (default is ~14).
- [ ] **Fix vertical alignment — it sits too high.** Text glyphs align on their
      baseline, not the optical centre of the menu bar. Fix with a baseline
      offset on an attributed title:
      `NSAttributedString(string:, attributes: [.baselineOffset: -1])`
      (tune the value), or better, switch to an image (below) which aligns
      properly by default.
- [ ] **Replace the glyph with an SF Symbol.**
      `button.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription:)`
      plus `withSymbolConfiguration(.init(pointSize:weight:))`, and set
      `image.isTemplate = true` so it adapts to light/dark menu bars. This
      solves sizing and alignment properly instead of nudging a text baseline.
- [ ] **Consider making size/offset config keys** (`menuBarIconSize`,
      `menuBarIconOffset`) so they can be changed without a rebuild. Worth it if
      this is ever published — other people will have opinions about the icon,
      and "edit config.json, restart" beats "recompile".
- [ ] The paused-state glyph is currently `◌`. Revisit once the icon is an SF
      Symbol; a filled/slashed variant of the same symbol would read better than
      a different character.

---

## Unverified behaviour (highest value work)

Verified working: native AppKit text (TextEdit et al.), Finder must-not-fire,
launchd start with its own permission, non-string clipboard preserved.

- [ ] **Browsers are completely untested.** The WebKit text-marker path
      (`AXSelectedTextMarkerRange` + `AXStringForTextMarkerRange`) and the
      Chromium `AXManualAccessibility` toggle were both added in response to a
      review that measured the problem, but neither has ever run. Test Safari
      and Chrome; if they fail, this is the biggest functional gap.
- [ ] **The ⌘C fallback has never executed.** All the delicate logic — modifier
      waiting, `changeCount` polling, snapshot/restore, the pre-post password
      re-check — is unexercised. Either deliberately trigger it (a Java/Qt app,
      or something with poor accessibility support) or decide the accessibility
      path is enough and ship `enableCopyFallback: false` as the default.
- [ ] **Finish the must-not-fire matrix:** title-bar double-click (window zoom),
      tmux/vim with mouse reporting, text drag-and-drop within a document, and
      **password fields** (native, Safari, Chrome) — the last one deliberately
      and carefully, since it is the failure that would end the project's
      credibility.
- [ ] Endurance: leave it running 1h+ idle, then select, to prove the
      `.tapDisabledByTimeout` re-enable path actually fires.
- [ ] Behaviour alongside a clipboard manager (Maccy/Raycast) — history
      pollution is the most likely day-to-day complaint.

---

## Known limitations carried over from review

Consciously accepted for now; revisit if they bite.

- [ ] **`AXObserver` on `kAXSelectedTextChangedNotification` is the better
      architecture** and was never built. It fires on the *actual* selection
      change instead of inferring from mouse geometry, which would remove the
      stale-selection class of bug entirely **and deliver keyboard selections
      (⇧+arrows, ⌘A) for free** — currently unsupported. Coverage is
      app-dependent, so it would be an additional trigger, not a replacement.
- [ ] **`frontmost == targetPID` in `isSafeToSynthesizeCopy` is too strict.** It
      will drop legitimate cases where the click did not activate the app —
      click-through, non-activating/floating panels — and any app whose AX
      elements report a helper process id.
- [ ] **`IsSecureEventInputEnabled()` is session-global.** Anyone with Terminal's
      "Secure Keyboard Entry" switched on has the ⌘C fallback disabled
      everywhere, permanently, with no indication why. Worth surfacing in the
      menu bar if the fallback is kept.
- [ ] **The ancestor walk never re-checks the pid of the answering element.**
      Latent rather than active (the parent chain reported the host process at
      every level in testing), but out-of-process web content could in principle
      return an element owned by a different process than the one the exclusion
      list was checked against.
- [ ] **`Clipboard.restore` deliberately skips restoring concealed and
      password-manager flavors**, which means a destroyed clipboard stays
      destroyed in exactly those cases. That is the safer failure (restoring
      would orphan a password manager's auto-clear and leave a secret on the
      clipboard indefinitely), but it is a real trade and should be documented
      for users, not just in a code comment.
- [ ] **App Sandbox was never evaluated.** `com.apple.security.network.client`
      being absent would make "no network access" kernel-enforced and verifiable
      with one `codesign -d --entitlements` call, which is far stronger than
      "grep the source". Unknown whether the sandbox is compatible with
      `CGEventTap` plus unscoped Accessibility — that is the question to answer.
- [ ] `.unsafeFlags` in `Package.swift` prevents this being consumed as a SwiftPM
      dependency. Fine for a leaf executable; note it if that ever changes.

---

## Distribution (decide before publishing)

The self-signed `copy-on-select-local` certificate is **local only** — it is
worthless for distributing to anyone else. Since macOS Sequoia the old
Control-click → Open bypass is gone, so an unsigned download means the user has
to go to System Settings → Privacy & Security → Open Anyway with an admin
password. Not a viable default experience.

Ranked options:

- [ ] **DECIDED (2026-07-25): Homebrew is the distribution route.**
      **Homebrew formula (builds from source)** — the natural fit. One command,
      and it *preserves* the build-it-yourself property the README argues for.
      Needs only the **Command Line Tools**, not Xcode (verified: CLT ships
      `swift`, `swiftc`, `swift-build`), and Homebrew requires CLT anyway — so
      brew users need nothing extra.
- [ ] **GitHub Actions + artifact attestation** — a Sigstore-signed statement
      that a specific binary came from a specific workflow, repo and commit,
      verified with `gh attestation verify`. Free, and default-on for public
      repos. **This is the direct answer to the README's own complaint** that
      signing and notarization never prove a binary matches its source — the
      project would demonstrate its argument rather than just state it.
- [ ] **Homebrew bottles** — prebuilt binaries from CI attached to Releases, so
      `brew install` does no compiling. Formula installs avoid the quarantine
      treatment casks get. Pair with attestation so the prebuilt binary is still
      verifiable. (Confirm the quarantine behaviour when implementing.)
- [ ] **Apple notarization ($99/yr)** — only if it gets popular. Buys the
      frictionless double-click *and* removes the certificate wizard from
      `install.md` (a Developer ID gives the stable identity that preserves the
      Accessibility grant). But it buys less here than for most apps, since the
      user must visit System Settings for Accessibility regardless — and alone
      it reintroduces "trust my build", so it should be paired with attestation.

## Before publishing

- [ ] **Review the README text with Eugene.** Required, not optional.
- [ ] **Measure the real line count** and fix any claim that implies "~60 lines".
      Currently ~1300 including comments; the core selection→clipboard logic is
      much smaller and can be pointed at specifically.
- [ ] Check `copy-on-select` is available as a repo name.
- [ ] Push the real multi-commit history, not a squashed import.
- [ ] Confirm the GitHub noreply identity is on every commit (a `pre-push` hook
      already enforces this).
- [ ] **Never push without explicit confirmation.**
