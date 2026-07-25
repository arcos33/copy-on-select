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

        case .leftMouseUp:
            guard isEnabled else { return }
            // Without a matching mouse-down (first event after launch, or after
            // the tap was re-enabled mid-drag) the down point is stale and the
            // hit test would target an unrelated element.
            guard hasDown else { return }
            hasDown = false

            let clickCount = event.getIntegerValueField(.mouseEventClickState)
            let shiftHeld = event.flags.contains(.maskShift)

            guard isSelectionCandidate(
                down: downLocation, up: event.location,
                clickCount: clickCount, shiftHeld: shiftHeld)
            else { return }

            schedule(at: downLocation)

        default:
            break
        }
    }

    /// A gesture is a candidate when it plausibly changed a text selection.
    ///
    /// Shift-click must be handled explicitly: it extends a selection without
    /// moving the mouse, so the drag test alone misses it and "extend the
    /// selection" appears broken.
    private func isSelectionCandidate(
        down: CGPoint, up: CGPoint, clickCount: Int64, shiftHeld: Bool
    ) -> Bool {
        let dx = up.x - down.x
        let dy = up.y - down.y
        let dragged = (dx * dx + dy * dy).squareRoot() > config.dragThreshold
        return dragged || clickCount >= 2 || shiftHeld
    }

    private func schedule(at point: CGPoint) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.resolveSelection(at: point)
        }
        pending = work
        queue.asyncAfter(
            deadline: .now() + .milliseconds(config.settleMilliseconds), execute: work)
    }

    // MARK: - Selection resolution (on `queue`, never on the tap callback)

    private func resolveSelection(at point: CGPoint) {
        // Rung 1: the element that was actually clicked. Starting here — rather
        // than from the focused element — is what makes the result attributable
        // to this gesture instead of to whatever is selected elsewhere.
        guard let clicked = AX.element(at: point) else {
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

        switch AX.findSelection(
            from: clicked, maxDepth: config.maxAncestorWalk, maxCharacters: config.maxCharacters)
        {
        case .text(let text):
            commit(text)
            return
        case .secure:
            // A password field was on the path. Copy nothing, and do not fall
            // back to synthesizing a keystroke.
            return
        case .none:
            break
        }

        // Gated fallback: only for a narrow set of genuine text roles whose
        // selection could not be read. Anything else — labels, rows, canvases,
        // Finder items, title bars — drops here.
        guard config.enableCopyFallback, AX.isFallbackRole(clicked) else { return }
        guard isSafeToSynthesizeCopy(targetPID: pid) else { return }

        fallbackQueue.async { [weak self] in
            self?.copyFallback()
        }
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

    private func commit(_ text: String) {
        // No separate "freshness" bookkeeping: Clipboard.write already skips a
        // write whose content equals the current clipboard, which is the same
        // check without the false negatives a cached key would introduce.
        let concealed = config.markClipboardConcealed
        DispatchQueue.main.async {
            Clipboard.write(text, concealed: concealed)
        }
    }

    // MARK: - Cmd+C fallback

    /// Synthesizes ⌘C, then restores the previous clipboard only if the copy
    /// actually damaged it.
    ///
    /// All pasteboard access here happens on this one queue, so reads and
    /// writes are not split across threads.
    private func copyFallback() {
        let snapshot = Clipboard.snapshot()

        // Extending a selection means Shift is often physically held. Posting
        // ⌘C then risks the app receiving ⇧⌘C, a different shortcut. Read the
        // modifier state rather than tapping keyboard events.
        waitForModifiersToClear(timeout: 0.15)

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
        guard changed else { return }

        if produced == nil {
            Clipboard.restore(snapshot)
        }
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
