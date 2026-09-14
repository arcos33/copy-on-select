import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Turns mouse events into clipboard writes.
///
/// Ordering matters and is the whole safety argument:
///
///   1. Classify the gesture (drag / multi-click / shift-click).
///   2. Settle, so the target app has finished updating its AX state.
///   3. Hit-test the element that was actually clicked, and take the owning
///      process FROM THAT ELEMENT — not from the event, and not from whatever
///      happens to be frontmost after the settle delay.
///   4. Check exclusions against that process, then ask accessibility what is
///      selected, walking up from the clicked element.
///   5. Only synthesize Cmd+C when we are in a narrow set of genuine text roles
///      whose selection could not be read.
///
/// Step 3 is what makes the result attributable to this gesture, and step 5 is
/// what stops the tool from clobbering the clipboard when it cannot tell what
/// happened.
final class Engine {
    private let queue = DispatchQueue(label: "dev.copy-on-select.engine", qos: .userInitiated)
    /// The fallback blocks (waiting on modifiers, polling the pasteboard), so it
    /// gets its own queue and cannot stall subsequent selections.
    private let fallbackQueue = DispatchQueue(label: "dev.copy-on-select.fallback", qos: .utility)

    private let config: Config
    private var tap: EventTap?
    private var pending: DispatchWorkItem?

    /// Gesture state. Only touched from the event-tap callback, which runs on
    /// the main run loop, so no synchronisation is needed.
    private var downLocation: CGPoint = .zero
    private var hasDown = false

    private(set) var isEnabled = true

    init(config: Config) {
        self.config = config
    }

    // MARK: - Lifecycle

    /// Starts the tap. Returns false when accessibility trust is missing.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let tap = EventTap { [weak self] type, event in
            self?.handle(type: type, event: event)
        }
        guard tap.start() else { return false }
        self.tap = tap
        // A grant can arrive after the user already paused; starting must not
        // silently resume observation.
        tap.setEnabled(isEnabled)
        return true
    }

    /// Pausing disables the tap itself rather than just ignoring events, so a
    /// paused app genuinely observes nothing.
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        tap?.setEnabled(enabled)
    }

    var isTapActive: Bool { tap?.isActive ?? false }

    /// Accessibility can be revoked while we run. Surfacing that is better than
    /// appearing alive but doing nothing.
    var isHealthy: Bool { AX.isTrusted && (isEnabled ? isTapActive : tap != nil) }

    // MARK: - Event handling (main run loop; must stay trivial)

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown:
            downLocation = event.location
            hasDown = true
            // Clipboard baseline is captured at gesture START, not mouse-up.
            // A user who finishes a drag and hits Cmd+C in one motion can land
            // the copy before a mouse-up baseline would be taken, absorbing it
            // into the baseline and blinding every later check. Anything
            // written after the drag began is foreign. (Dispatched: no IPC in
            // the tap callback.)
            queue.async { [weak self] in
                self?.clipboardBaseline = Clipboard.changeCount
            }

        case .leftMouseUp:
            guard isEnabled else { return }
            // Without a matching mouse-down (first event after launch, or after
            // the tap was re-enabled mid-drag) the down point is stale and the
            // hit test would target an unrelated element.
            guard hasDown else { return }
            hasDown = false

            let clickCount = event.getIntegerValueField(.mouseEventClickState)
            let shiftHeld = event.flags.contains(.maskShift)

            let dx = event.location.x - downLocation.x
            let dy = event.location.y - downLocation.y
            let dragged = (dx * dx + dy * dy).squareRoot() > config.dragThreshold

            guard dragged || clickCount >= 2 || shiftHeld else { return }

            schedule(down: downLocation, up: event.location, wasDrag: dragged)

        default:
            break
        }
    }

    /// Whether the gesture plausibly interacted with the selection's on-screen
    /// rectangle. Endpoint-based on purpose: a genuine selection gesture has
    /// its endpoints at or inside the selection, while a drag that merely
    /// CROSSES stale text (dragging a card over a paragraph) has both
    /// endpoints outside and is rejected - stricter than segment intersection.
    private func gestureTouches(_ bounds: CGRect, down: CGPoint, up: CGPoint) -> Bool {
        // Padding absorbs the few points of slop between where the click
        // lands and where the app draws the selection.
        let padded = bounds.insetBy(dx: -12, dy: -12)
        return padded.contains(down) || padded.contains(up)
    }

    private func schedule(down: CGPoint, up: CGPoint, wasDrag: Bool) {
        pending?.cancel()
        let gen = nextGeneration()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resolveSelection(
                down: down, up: up, wasDrag: wasDrag, generation: gen,
                clipboardBaseline: self.clipboardBaseline)
        }
        pending = work
        queue.asyncAfter(
            deadline: .now() + .milliseconds(config.settleMilliseconds), execute: work)
    }

    /// Only touched on `queue`.
    private var clipboardBaseline = 0

    // MARK: - Selection resolution (on `queue`, never on the tap callback)

    /// Bumped on every new gesture. A resolution that finds itself stale by the
    /// time it finishes discards its result rather than writing an outdated
    /// selection — the native-copy path can take a few hundred milliseconds,
    /// which is long enough for the user to have moved on.
    private let generationLock = NSLock()
    private var generation = 0

    private func nextGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        generation += 1
        return generation
    }

    private func isCurrent(_ value: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return value == generation
    }

    private func resolveSelection(
        down: CGPoint, up: CGPoint, wasDrag: Bool, generation gen: Int, clipboardBaseline: Int
    ) {
        // Rung 1: the element that was actually clicked. Starting here — rather
        // than from the focused element — is what makes the result attributable
        // to this gesture instead of to whatever is selected elsewhere.
        guard let clicked = AX.element(at: down) else {
            // Nothing under the cursor exposes accessibility, so we cannot tell
            // whether a selection happened. Guessing here is what produces
            // wrong-clipboard bugs.
            return
        }

        // The owning process of the element we are about to read. Taken from
        // the element rather than the event because the event's target-pid is
        // not reliably populated at a session tap, and because the window under
        // the cursor may have changed during the settle delay.
        guard let pid = AX.pid(of: clicked), !isExcluded(pid: pid) else { return }

        // Chromium keeps its web-content AX tree off until an assistive client
        // asks. Requested once per process; takes effect for later gestures.
        AX.enableManualAccessibilityIfNeeded(pid: pid)

        switch AX.findSelection(
            from: clicked, maxDepth: config.maxAncestorWalk, maxCharacters: config.maxCharacters)
        {
        case .secure:
            // A password field was on the path. Copy nothing, and never
            // synthesize a keystroke.
            return

        case .tooLarge:
            // A selection exists but exceeds the cap. Falling through to a
            // native copy would copy it anyway, defeating the cap.
            return

        case .text(let axText, let selectionBounds):
            // The gesture must touch the selection. A drag that selects text
            // traces across it, a double-click lands inside it, a shift-click
            // ends at its boundary - but a drag on a card, splitter or
            // scrollbar in a document that still holds an OLD selection does
            // not go anywhere near that selection's rectangle. This geometric
            // test is what stops a non-selection drag from re-copying stale
            // text. Fail-open: apps that cannot report bounds behave as
            // before.
            if config.requireGestureNearSelection, wasDrag,
                let selectionBounds, !selectionBounds.isEmpty,
                !gestureTouches(selectionBounds, down: down, up: up)
            {
                return
            }
            // Accessibility has confirmed a safe, non-empty selection, and has
            // given us a usable value. Everything past this point is about
            // FIDELITY, not about whether to copy.

            // Something else copied while we were resolving — a terminal's own
            // copy-on-select, most likely. Its result is authoritative for its
            // own content; do not overwrite it. Our own just-landed write for a
            // previous gesture is not "something else".
            let observedCount = Clipboard.changeCount
            if config.yieldToExistingCopy,
                observedCount != clipboardBaseline, !isOwnWrite(observedCount)
            {
                return
            }

            guard shouldUseNativeCopy(pid: pid) else {
                guard isCurrent(gen) else { return }
                commit(axText, force: false, guardCount: observedCount)
                return
            }

            // The app's own copy preserves list markers, numbering and line
            // breaks that accessibility flattens. It runs off this queue
            // because it blocks for up to half a second, and the settle timers
            // for later gestures are scheduled here.
            fallbackQueue.async { [weak self] in
                guard let self, self.isCurrent(gen) else { return }
                let native = self.nativeCopy(
                    targetPID: pid, generation: gen, restoreOnFailure: false)
                guard self.isCurrent(gen) else { return }

                // Use the app's version only if it is recognisably the same
                // selection accessibility just confirmed. This is what stops a
                // copy handler on a web page from substituting its own text,
                // and what catches the app copying a different pane's
                // selection than the one under the cursor.
                if let native, native.count <= self.config.maxCharacters,
                    self.corresponds(native: native, accessibility: axText)
                {
                    // Force the rewrite: the string already matches what the
                    // app put on the pasteboard, and rewriting is what strips
                    // its styling flavors.
                    self.commit(native, force: self.config.plainTextOnly)
                } else {
                    self.commit(axText, force: false)
                }
            }
            return

        case .none:
            break
        }

        // Last resort, off by default: accessibility found no selection at all.
        // Firing here is a guess, which is why it beeps in apps where nothing
        // was actually selected. There is no accessibility text to compare
        // against or fall back to, so this path is inherently less trustworthy.
        guard config.enableCopyFallback, AX.isFallbackRole(clicked) else { return }
        if config.yieldToExistingCopy {
            let current = Clipboard.changeCount
            if current != clipboardBaseline, !isOwnWrite(current) { return }
        }
        fallbackQueue.async { [weak self] in
            guard let self, self.isCurrent(gen) else { return }
            // restoreOnFailure: this path has no accessibility text to fall
            // back to, so a copy that damaged the clipboard without producing
            // text must put the previous contents back.
            guard let native = self.nativeCopy(
                    targetPID: pid, generation: gen, restoreOnFailure: true),
                native.count <= self.config.maxCharacters
            else { return }
            guard self.isCurrent(gen) else { return }
            self.commit(native, force: self.config.plainTextOnly)
        }
    }

    /// Whether this app's own copy should be preferred over the accessibility
    /// text for the same selection. The disabled list wins even in
    /// everywhere-mode, so there is always a per-app escape hatch.
    private func shouldUseNativeCopy(pid: pid_t) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return false
        }
        if config.nativeCopyDisabledApps.contains(bundleID) { return false }
        if config.preferNativeCopyEverywhere { return true }
        return config.preferNativeCopyApps.contains(bundleID)
    }

    /// Whether the app's copy is recognisably the same selection accessibility
    /// reported.
    ///
    /// The legitimate difference between the two is exactly list markers,
    /// numbering and whitespace — which is why those are stripped before
    /// comparing. Anything left over is content that was not in the selection:
    /// a page's copy handler appending its own text, or the app copying a
    /// different selection than the one under the cursor.
    private func corresponds(native: String, accessibility: String) -> Bool {
        let a = Self.normalizeForComparison(native)
        let b = Self.normalizeForComparison(accessibility)
        if a == b { return true }
        guard !b.isEmpty else { return false }

        // Subsequence, not substring: everything accessibility saw must appear
        // in the native copy, in order, but the native copy may interleave
        // extras. The legitimate extras are exactly numbered-list digits —
        // "1. First 2. Second" against accessibility's "First Second" — which
        // a contains() check wrongly rejects because the digits interrupt the
        // match. An attacker is still stuck: nothing can be removed or
        // replaced, and additions are capped by the slack.
        var extra = 0
        var remainder = b[...]
        for character in a {
            if let next = remainder.first, character == next {
                remainder = remainder.dropFirst()
            } else {
                extra += 1
            }
        }
        guard remainder.isEmpty else { return false }
        let slack = max(20, b.count / 10)
        return extra <= slack
    }

    private static func normalizeForComparison(_ text: String) -> String {
        let markers: Set<Character> = ["•", "◦", "▪", "‣", "-", "–", "—", "*", ".", ")"]
        return String(
            text.lowercased().filter { character in
                !character.isWhitespace && !markers.contains(character)
            })
    }

    private func isExcluded(pid: pid_t) -> Bool {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            // Unknown app: treat as excluded. Failing closed is right here.
            return true
        }
        return config.excludedBundleIDs.contains(bundleID)
    }

    /// The password check above applies to the element we hit-tested, but a
    /// synthetic ⌘C goes to whatever holds *keyboard focus*, which need not be
    /// the same thing. These three checks close that gap.
    private func isSafeToSynthesizeCopy(targetPID: pid_t) -> Bool {
        // 1. macOS is in secure input mode (a password field is focused
        //    somewhere). Never synthesize keystrokes in that state.
        if IsSecureEventInputEnabled() { return false }

        // 2. The focused element is itself a password field.
        if let focused = AX.focusedElement(), AX.isSecure(focused) { return false }

        // 3. The keystroke would be delivered to the app we actually read from.
        guard let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier,
            frontmost == targetPID
        else { return false }

        return true
    }

    /// The changeCount produced by our own most recent write. Needed by the
    /// yield check: our commit for gesture N lands on the main queue slightly
    /// after gesture N+1 captured its baseline, so without this, the app's own
    /// write looks like a third party copying and N+1 wrongly yields.
    private let ownWriteLock = NSLock()
    private var lastOwnWriteCount = -1

    private func noteOwnWrite(_ count: Int) {
        ownWriteLock.lock()
        lastOwnWriteCount = count
        ownWriteLock.unlock()
    }

    private func isOwnWrite(_ count: Int) -> Bool {
        ownWriteLock.lock()
        defer { ownWriteLock.unlock() }
        return count == lastOwnWriteCount
    }

    /// `guardCount`: the clipboard changeCount the caller last observed. The
    /// write aborts if the clipboard has moved past it by the time the write
    /// executes — unless the newer write was our own. This check runs on the
    /// same queue as the write itself, closing the gap in which a user's
    /// manual ⌘C (or any other copy) could land between our decision to write
    /// and the write executing. The recorded failure: the user's rich manual
    /// copy landed ~300ms before our flattened write and was clobbered, with
    /// the earlier worker-queue yield check unable to see it.
    private func commit(_ text: String, force: Bool, guardCount: Int? = nil) {
        // No separate "freshness" bookkeeping: Clipboard.write already skips a
        // write whose content equals the current clipboard, which is the same
        // check without the false negatives a cached key would introduce.
        let concealed = config.markClipboardConcealed
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let guardCount {
                let current = Clipboard.changeCount
                if current != guardCount, !self.isOwnWrite(current) { return }
            }
            // Timing-proof half of the protection: if the clipboard already
            // holds a RICH-flavored copy of this same text (the user's own
            // Cmd+C, whenever it landed - even before our baseline), a plain
            // rewrite would only downgrade it. Skip. `force` writes are the
            // deliberate flavor-stripping path and are exempt.
            if !force, let existing = Clipboard.currentString {
                let pasteboardTypes = (NSPasteboard.general.types ?? []).map(\.rawValue)
                let isRich = pasteboardTypes.contains {
                    $0.lowercased().contains("rtf") || $0.lowercased().contains("html")
                        || $0.lowercased().contains("web")
                }
                if isRich,
                    Self.normalizeForComparison(existing) == Self.normalizeForComparison(text)
                {
                    // The target app already performed the equivalent native
                    // copy. It is still a successful automatic copy, so give
                    // the same confirmation without rewriting its rich data.
                    CopyToast.shared.show()
                    return
                }
            }
            if let count = Clipboard.write(text, concealed: concealed, force: force) {
                self.noteOwnWrite(count)
                CopyToast.shared.show()
            } else if Clipboard.currentString == text {
                // A matching plain-text item makes the write a deliberate
                // no-op. The selection was nevertheless confirmed, and the
                // user should get the same feedback as for a fresh write.
                CopyToast.shared.show()
            }
        }
    }

    // MARK: - Cmd+C fallback

    /// Asks the app to copy its own selection, and returns the resulting plain
    /// text — or nil if the copy did not produce anything usable.
    ///
    /// Returning the text rather than leaving it on the pasteboard lets the
    /// caller decide: on success the value is rewritten as plain text only, and
    /// on failure the caller falls back to the accessibility text it already
    /// holds. Either way the clipboard is restored if this damaged it.
    /// `restoreOnFailure` should be false when the caller already holds the
    /// accessibility text: it will commit that immediately, so restoring the
    /// previous clipboard first is a wasted write that briefly shows stale
    /// content and adds a spurious clipboard-manager entry.
    private func nativeCopy(
        targetPID: pid_t, generation gen: Int, restoreOnFailure: Bool
    ) -> String? {
        guard isSafeToSynthesizeCopy(targetPID: targetPID) else { return nil }

        let snapshot = Clipboard.snapshot()

        // Extending a selection means Shift is often physically held. Posting
        // ⌘C then risks the app receiving ⇧⌘C, a different shortcut. Read the
        // modifier state rather than tapping keyboard events.
        waitForModifiersToClear(timeout: 0.15)

        // Re-check immediately before posting. The safety checks ran earlier;
        // during the modifier wait, secure input can switch on, focus can move
        // to a password field, or another app can come forward — and the
        // keystroke goes wherever focus is *now*.
        guard isSafeToSynthesizeCopy(targetPID: targetPID) else { return nil }

        // Posting is a side effect on the user's clipboard, so it must not
        // happen for a gesture that has already been superseded.
        guard isCurrent(gen) else { return nil }

        postCommandC()

        // Wait for the pasteboard to change AND to carry usable text. Breaking
        // as soon as changeCount moves is a race: an app bumps the count in
        // clearContents() and sets the string flavor afterwards, so an
        // immediate read can see nothing and wrongly conclude the copy failed.
        let deadline = Date().addingTimeInterval(0.4)
        var changed = false
        var produced: String?

        while Date() < deadline {
            if NSPasteboard.general.changeCount != snapshot.changeCount {
                changed = true
                let candidate = NSPasteboard.general.string(forType: .string)
                if let candidate,
                    !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    produced = candidate
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        // Nothing happened: the clipboard is already untouched. Restoring here
        // would be destructive, not neutral — it bumps changeCount, flattens
        // promised flavors, adds a duplicate clipboard-manager entry, and can
        // orphan a password manager's pending auto-clear.
        guard changed else { return nil }

        // The app's write was induced by OUR keystroke, so record it as our
        // own — unconditionally, before any generation check. A superseded
        // gesture that skips its commit must not leave this write looking
        // foreign, or the next gesture's yield check wrongly backs off and the
        // clipboard keeps the older selection.
        noteOwnWrite(NSPasteboard.general.changeCount)

        guard let produced else {
            // The copy damaged the clipboard without producing text. Restore
            // only if the caller has nothing else to write.
            if restoreOnFailure {
                DispatchQueue.main.async { Clipboard.restore(snapshot) }
            }
            return nil
        }
        return produced
    }

    private func waitForModifiersToClear(timeout: TimeInterval) {
        let interesting: CGEventFlags = [.maskShift, .maskCommand, .maskControl, .maskAlternate]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(interesting).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func postCommandC() {
        let virtualKeyC = CGKeyCode(kVK_ANSI_C)
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyC, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyC, keyDown: false)
        else { return }
        // Set flags explicitly so held modifiers cannot turn this into a
        // different shortcut.
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
