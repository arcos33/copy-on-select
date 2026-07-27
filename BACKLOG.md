# Backlog

Things worth doing the next time this gets rebuilt. Nothing here is urgent —
the app works — so these are batched deliberately rather than triggering a
rebuild each on their own.

**Rebuild cost, for reference:** `swift build -c release` → `codesign` with
`copy-on-select-local` → copy to `~/Applications` → `launchctl unload/load`.
About 30 seconds. **The Accessibility grant survives**, because the stable
self-signed certificate keeps the binary's identity constant across rebuilds —
that is the whole reason for using a certificate instead of ad-hoc signing.

---

## Menu bar icon

**Shipped 2026-07-25:** SF Symbol `doc.on.doc` at 13.6pt, nudged 2px down via a
padded canvas (the status item centres its image), tuned by eye with Eugene.
Distinct symbols for active / paused (`pause.circle`) / unhealthy
(`exclamationmark.triangle`), template mode for light/dark menu bars.

- [ ] **Consider making size/offset config keys** (`menuBarIconSize`,
      `menuBarIconOffset`) so future tweaks need no rebuild. Worth it if this is
      published — other people will have opinions about the icon.

---

## Verification status (refreshed 2026-07-25 end of day)

**Verified in real use:** native AppKit text (TextEdit, Stickies, Notes);
**Safari via text markers** (structure + styles); **Chrome and Linear**
(live-probed and in daily use); the **native-⌘C path runs constantly** as the
everywhere default (styled copies confirmed by flavor inspection); numbered
lists survive (subsequence check); rapid-fire selections; the **fast-⌘C race**
(reproduced by Eugene, recorded by clipwatch, fixed by mouse-down baseline +
write-time guard + rich-equivalence skip, then re-confirmed by Eugene); **B1
live-tested** (Linear card drag left `MARKER 42` intact); Finder must-not-fire;
non-string clipboard preserved; launchd start on its own grant.

**Still unverified — ranked:**

- [x] **Password fields — behaviourally verified 2026-07-26** (Safari and
      Chrome, tested by Eugene with deliberate selections: nothing reached the
      clipboard). Honest caveats, accepted to save time: the *mechanism* is
      unconfirmed — the protection could be our explicit `AXSecureTextField`
      check firing, or the field simply exposing no selection over
      accessibility (protection by accident, which a browser update could
      change silently). Native `NSSecureTextField` fields were not tested.
      If this is ever revisited: probe a password field for whether a
      selection is exposed at all and whether the secure role is detected.
- [ ] tmux/vim with mouse reporting; title-bar double-click; text drag-and-drop
      within a document.
- [ ] The **blind last-resort path** (`enableCopyFallback`, off by default) —
      still never executed; its only real-world appearance was the old Stickies
      beep. Fine to leave off and untested; do not enable without testing.
- [ ] Endurance: the `.tapDisabledByTimeout` re-enable path specifically. (The
      app survived a full day of heavy use, but the tap never provably died of
      a timeout — the one death observed was the since-fixed IPC bug.)
- [ ] Behaviour alongside a clipboard manager (Maccy/Raycast) — history
      pollution is the most likely day-to-day complaint.

---

## Cursor: settled per-pane behaviour (decided 2026-07-25, don't re-litigate)

Cursor is the most hostile app we support — Electron webviews, a canvas editor,
an embedded TUI, multi-pane focus. Settled state:

- **Markdown source editor (Monaco): NOT supported — final decision 2026-07-25,
  don't re-litigate.** Copying there works only with Cursor's
  `editor.accessibilitySupport: "on"` (confirmed empirically; applies live, no
  reload). But that mode puts Monaco into screen-reader optimization, which
  **disables word wrap** among other effects, and Eugene weighed the trade and
  chose word wrap. With the setting off, the element under the cursor is an
  `AXImage` and no selection is exposed at any depth (measured twice), so no
  accessibility route exists. Manual ⌘C works there (Monaco-internal). Note:
  Cursor overwrites external edits to its settings.json while running — any
  future change must be made in Cursor's own settings UI.
- **Preview pane: accessibility text only** (Cursor is in
  `nativeCopyDisabledApps`). Correct plain text, no styles, and the first
  bullet of a list is missing when the drag starts on the text (the `•` is a
  ::marker pseudo-element outside the selected range — selection-boundary
  behaviour, not a bug). **The cause of the old native-path failure is
  unproven:** the wrong-pane/focus story was inference, and evidence now cuts
  against it — Eugene's manual ⌘C reaches Preview and produces the full rich
  copy (first bullet included). The failure may have been the since-fixed
  substring correspondence check. **Worth one measured retry:** re-enable
  native for Cursor and test Preview; if it works now, Preview gains styles,
  line breaks and the first bullet in one move.
- **Claude Code TUI pane: handles its own copying** (OSC 52); the yield check
  defers to it.

## From the second Fable review (2026-07-25) — accepted risks, not yet fixed

Bugs 1–4 of that review are fixed (own-write bookkeeping unconditional after a
⌘C-induced write; B1 scoped to drags because clicks get clamped by text views;
own-write count read inside Clipboard.write to shrink the misattribution
window; last-resort path restores again). Still open, ranked:

- [x] **Baseline timing — substantially closed 2026-07-25:** baseline is now
      captured at mouse-DOWN, a write-time guard re-checks the changeCount on
      the write's own queue immediately before writing, and a rich-equivalence
      skip refuses to downgrade an equivalent rich copy regardless of timing.
      Residual: the baseline block still runs on the serial queue and could be
      captured late behind a slow resolution — but the write-time guard now
      catches what a late baseline would have missed.
- [ ] **`markClipboardConcealed` silently ineffective on the native path**:
      with everywhere-native + plainTextOnly=false, commit is usually an
      equal-content skip, so the concealed marker never lands. If the flag is
      on, force the rewrite.
- [ ] **Correspondence false-rejects** → silent downgrade to flattened AX text:
      soft hyphens (U+00AD), ligatures, and screen-reader-only spans present in
      AX text but absent from the app's plain copy; long numbered lists with
      short items can blow the slack (≈2 digits/item vs 10%). Consider
      stripping soft hyphens + digits-adjacent-to-markers in normalization.
- [ ] **Slack admits ~20-char injections** — a page's copy handler can append a
      short string and pass. Disclosed in README as "same mechanism as manual
      ⌘C"; tighten to exact-subsequence-only in web contexts if it ever bites.
- [ ] **B1 vs momentum scroll**: bounds are fetched ~180ms after the gesture;
      a scroll in between moves the rect → rare false drop (and, inverted,
      a rare false pass). Live with it; revisit with AXObserver.
- [ ] `(` is kept while `)` is stripped in the normalization marker set.

## Apps measured as unsupported (manual ⌘C only — structural, not bugs)

- **Messages (com.apple.MobileSMS)** — measured 2026-07-25, 23 probe samples:
  the SwiftUI transcript exposes only anonymous `AXGroup` containers, no text
  roles, and answers no selection attribute by any mechanism. Nothing to read,
  and the no-AX-confirmation rule (correctly) blocks the synthetic ⌘C — which
  would otherwise copy a whole bubble when three words were selected. Also
  arguably an app privacy-minded users would exclude anyway.
- **Cursor Markdown source editor** — see the Cursor section above.

## Install format: .app bundle (decided 2026-07-27, after a TCC incident)

The bare-executable install format caused a real failure: after the signing
identity changed at a fixed path (self-signed -> Developer ID -> self-signed),
the stale TCC record shadowed every new Accessibility grant, the Settings "+"
picker could not even show the bare binary, and `tccutil` could not reset it
(no bundle identifier). Escape was a **fresh path + a real `.app` bundle**,
which is now the documented install format everywhere (install.md, Homebrew
formula revision 1). Same binary, same certificate — only the packaging shape
changed.

Hard-won corollary, now also a warning in install.md: **a Developer ID
signature without notarization is actively rejected by Gatekeeper** ("
Unnotarized Developer ID") and breaks Accessibility — strictly worse than
self-signed. Developer ID only helps as a signed+notarized pair. Eugene has a
Developer ID cert (his own company); notarization remains a deliberate,
separate future step that would also enable prebuilt releases/bottles — noting
that notarized binaries visibly carry the company name and Team ID, which the
current build-from-source model never exposes.

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

- [x] **SHIPPED (2026-07-25): Homebrew formula, builds from source.**
      Tap: `github.com/yauyauyauhen/homebrew-tap`, install via
      `brew install yauyauyauhen/tap/copy-on-select`. Tested end-to-end (built
      in 41s, formula test passes). Includes a `service` block so
      `brew services start` manages the LaunchAgent, and caveats explaining the
      Accessibility grant and that upgrades re-prompt it (new binary identity).
      Per release: bump URL + sha256 in the formula — two lines.
      **Gotcha for future releases:** GitHub can serve the tag tarball's 404
      page with HTTP 200 right after a tag push — verify the download is gzip
      before hashing, or the formula gets the hash of an error page.
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

## Publishing — DONE 2026-07-25

Published as `github.com/yauyauyauhen/copy-on-select`, tagged v0.1.0.

- [x] README reviewed with Eugene (he caught the placeholder install URL);
      Install section moved above the rationale, Homebrew added, agent-neutral
      wording.
- [x] Repo name was available.
- [x] Real multi-commit history pushed (private first, reviewed, then flipped
      public).
- [x] Noreply identity verified on every commit, both repos, author and
      committer; pre-push hooks installed in both.
- [x] Commit messages audited for anything personal or unprofessional: clean.
- [x] Hygiene scan (secrets, personal identifiers, .DS_Store, history): clean.
- [x] About description + topics set.

**Standing rules, still in force:** never push without Eugene's explicit
confirmation; the line-count claim in the README should be re-measured if it is
ever sharpened (currently it says "small enough to read", which stays true).
