import ApplicationServices
import Foundation

/// Thin wrappers over the Accessibility API.
///
/// Every call here is cross-process IPC and can block, so nothing in this file
/// may be called from the event-tap callback. See Engine.
enum AX {
    /// One hung app must not wedge the worker queue.
    static let messagingTimeout: Float = 0.25

    /// Roles that are unambiguously interactive controls rather than content.
    /// A click here is a click on a widget, so we never read a selection —
    /// neither from the element nor from its ancestors.
    ///
    /// Measured 2026-07-25: this is a *denylist* rather than an allowlist
    /// because real selections are frequently answered by `AXGroup`, `AXList`,
    /// `AXCell` and similar container roles at depth 0 — in Safari, Chrome and
    /// Linear alike. An allowlist of "text" roles silently dropped those, which
    /// made the app look like it randomly stopped working depending on which
    /// element the drag happened to start on.
    static let interactiveLeafRoles: Set<String> = [
        "AXButton",
        "AXPopUpButton",
        "AXMenuButton",
        "AXCheckBox",
        "AXRadioButton",
        "AXSlider",
        "AXIncrementor",
        "AXStepper",
        "AXDisclosureTriangle",
        "AXMenuItem",
        "AXMenuBarItem",
        "AXImage",
        "AXColorWell",
    ]

    /// Roles the clicked element must have before we are willing to look at its
    /// *ancestors* for a selection.
    ///
    /// Reading from an ancestor is the risky case: a click on a non-text
    /// descendant could otherwise pick up a container's unrelated, pre-existing
    /// selection. Depth 0 has no such ambiguity — if the element under the
    /// cursor answers, that selection is the one you clicked on — so this gate
    /// applies only from depth 1 upwards.
    static let leafTextRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXStaticTextRole as String,
        kAXComboBoxRole as String,
        "AXWebArea",
        "AXHeading",
        "AXLink",
    ]

    /// Roles worth *asking* for a selection while walking up. Broader than the
    /// leaf gate, because browsers and PDF views implement the selection on a
    /// generic container above the text node.
    static let readableRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXStaticTextRole as String,
        kAXComboBoxRole as String,
        kAXGroupRole as String,
        kAXScrollAreaRole as String,
        kAXRowRole as String,
        kAXCellRole as String,
        "AXWebArea",
        "AXHeading",
        "AXLink",
    ]

    /// Roles allowed to trigger the synthetic ⌘C fallback. Much narrower than
    /// `readableRoles` on purpose.
    ///
    /// `AXStaticText` must NOT be here. It is the role of every label on macOS
    /// — table cells, sidebar items, list rows — and it never implements
    /// `AXSelectedText`. Including it would send ⌘C on any double-click of a
    /// label (e.g. a row in Mail's message list, which copies the whole
    /// message), producing precisely the wrong-clipboard events this project
    /// exists to prevent.
    static let fallbackRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXComboBoxRole as String,
        "AXWebArea",
    ]

    /// Password fields. Secure Input Mode does NOT protect the accessibility
    /// path — it only suppresses keyboard taps and synthetic keystrokes — so
    /// this check is the actual protection.
    static let secureRoles: Set<String> = [
        "AXSecureTextField"
    ]

    static func systemWide() -> AXUIElement {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        guard let value = attribute(element, name) else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        let text = value as! CFString as String
        return text
    }

    static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute as String)
    }

    static func subrole(_ element: AXUIElement) -> String? {
        string(element, kAXSubroleAttribute as String)
    }

    /// The owning process of an element.
    ///
    /// This — not the event's target-pid field — is the authoritative answer to
    /// "which app is this selection coming from", because it is derived from
    /// the element we are actually about to read.
    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    /// True when this element is a password field, by role or subrole. Web
    /// password inputs surface as a text field with a secure subrole rather
    /// than a secure role, so both must be checked.
    static func isSecure(_ element: AXUIElement) -> Bool {
        if let role = role(element), secureRoles.contains(role) { return true }
        if let subrole = subrole(element), secureRoles.contains(subrole) { return true }
        return false
    }

    static func isReadableRole(_ element: AXUIElement) -> Bool {
        guard let role = role(element) else { return false }
        return readableRoles.contains(role)
    }

    static func isFallbackRole(_ element: AXUIElement) -> Bool {
        guard let role = role(element) else { return false }
        return fallbackRoles.contains(role)
    }

    /// The element directly under a screen point. Point must be in top-left
    /// origin screen coordinates, which is what CGEvent.location gives us.
    static func element(at point: CGPoint) -> AXUIElement? {
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(
            systemWide(), Float(point.x), Float(point.y), &element)
        guard result == .success, let element else { return nil }
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func focusedElement() -> AXUIElement? {
        guard let value = attribute(systemWide(), kAXFocusedUIElementAttribute as String) else {
            return nil
        }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func parent(_ element: AXUIElement) -> AXUIElement? {
        guard let value = attribute(element, kAXParentAttribute as String) else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let parent = value as! AXUIElement
        AXUIElementSetMessagingTimeout(parent, messagingTimeout)
        return parent
    }

    static func selectedText(_ element: AXUIElement) -> String? {
        string(element, kAXSelectedTextAttribute as String)
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute as String) else {
            return nil
        }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Some apps expose the range plus the parameterized string-for-range
    /// attribute without exposing kAXSelectedText.
    static func string(_ element: AXUIElement, forRange range: CFRange) -> String? {
        var mutableRange = range
        guard let axValue = AXValueCreate(.cfRange, &mutableRange) else { return nil }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            axValue,
            &result)
        guard status == .success, let result else { return nil }
        guard CFGetTypeID(result) == CFStringGetTypeID() else { return nil }
        let text = result as! CFString as String
        return text
    }

    // MARK: - Text markers (WebKit)

    /// WebKit exposes web-content selections through text markers only: Safari's
    /// AXWebArea answers neither `AXSelectedText` nor `AXSelectedTextRange`, but
    /// does answer `AXSelectedTextMarkerRange`. Without these two attributes,
    /// browsers silently produce nothing.
    static let selectedTextMarkerRangeAttribute = "AXSelectedTextMarkerRange"
    static let stringForTextMarkerRangeAttribute = "AXStringForTextMarkerRange"

    static func selectedTextViaMarkers(_ element: AXUIElement) -> String? {
        guard let markerRange = attribute(element, selectedTextMarkerRangeAttribute) else {
            return nil
        }
        var result: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            stringForTextMarkerRangeAttribute as CFString,
            markerRange,
            &result)
        guard status == .success, let result else { return nil }
        guard CFGetTypeID(result) == CFStringGetTypeID() else { return nil }
        let text = result as! CFString as String
        return text.isEmpty ? nil : text
    }

    /// Chromium-based apps (Chrome, Electron) keep their web-content
    /// accessibility tree switched off until an assistive client asks for it.
    /// Without this the hit test lands on a native container with no selection
    /// attributes at all.
    ///
    /// Setting it is idempotent and cheap; we only try once per process.
    private static var manualAccessibilityRequested = Set<pid_t>()
    private static let manualAccessibilityLock = NSLock()

    static func enableManualAccessibilityIfNeeded(pid: pid_t) {
        manualAccessibilityLock.lock()
        let alreadyDone = manualAccessibilityRequested.contains(pid)
        if !alreadyDone { manualAccessibilityRequested.insert(pid) }
        manualAccessibilityLock.unlock()
        guard !alreadyDone else { return }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    enum SelectionOutcome {
        /// A selection was read.
        case text(String)
        /// A password field was encountered; abort everything, copy nothing.
        case secure
        /// A selection exists but exceeds the size cap. Distinct from `.none`
        /// because it must NOT fall through to the Cmd+C fallback — doing so
        /// would copy the very selection the cap exists to avoid, by the more
        /// destructive route.
        case tooLarge
        /// Nothing readable found.
        case none
    }

    /// Walks up from the hit-tested element looking for one that can answer
    /// "what is selected".
    ///
    /// Browsers and PDF views hit-test to the deepest node while implementing
    /// the selection attributes on an ancestor (typically the `AXWebArea`), so
    /// without this walk those apps silently produce nothing and fall through
    /// to the riskier ⌘C path.
    ///
    /// `maxCharacters` is enforced against the *range length* before the text
    /// is fetched, so a Cmd+A selection in a huge document is rejected without
    /// marshalling megabytes across the AX boundary.
    static func findSelection(
        from element: AXUIElement, maxDepth: Int, maxCharacters: Int
    ) -> SelectionOutcome {
        // Role and subrole are fetched once per node and reused. Each AX call is
        // cross-process IPC, so re-asking per predicate is what made the walk
        // slow enough to matter.
        let leafRole = role(element)
        let leafSubrole = subrole(element)

        if isSecure(role: leafRole, subrole: leafSubrole) { return .secure }

        // A click on a control is not a text selection, at any depth.
        if let leafRole, interactiveLeafRoles.contains(leafRole) { return .none }

        // Ancestors are only consulted when the click landed on something
        // text-bearing; see leafTextRoles.
        let mayConsultAncestors = leafRole.map { leafTextRoles.contains($0) } ?? false

        var current: AXUIElement? = element
        var depth = 0

        while let node = current, depth < maxDepth {
            let nodeRole = depth == 0 ? leafRole : role(node)
            let nodeSubrole = depth == 0 ? leafSubrole : subrole(node)

            // Checked at every level: a secure field anywhere on the path means
            // stop entirely rather than continue up to a readable ancestor.
            if isSecure(role: nodeRole, subrole: nodeSubrole) { return .secure }

            // Depth 0 is always worth asking — container roles routinely answer.
            // Above that, restrict to roles that plausibly own a selection.
            let worthAsking =
                depth == 0
                ? true
                : (mayConsultAncestors && (nodeRole.map { readableRoles.contains($0) } ?? false))

            if worthAsking {
                if let text = selectedText(node), !text.isEmpty {
                    return text.count <= maxCharacters ? .text(text) : .tooLarge
                }

                // Only fetch the range once the cheap attribute has failed.
                if let range = selectedRange(node), range.length > 0 {
                    if range.length > maxCharacters { return .tooLarge }
                    if let text = string(node, forRange: range), !text.isEmpty {
                        return .text(text)
                    }
                }

                // WebKit answers neither of the above; markers are its only
                // route.
                if let text = selectedTextViaMarkers(node) {
                    return text.count <= maxCharacters ? .text(text) : .tooLarge
                }
            }

            current = parent(node)
            depth += 1
        }
        return .none
    }

    private static func isSecure(role: String?, subrole: String?) -> Bool {
        if let role, secureRoles.contains(role) { return true }
        if let subrole, secureRoles.contains(subrole) { return true }
        return false
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompting variant. This is also what creates the entry in
    /// System Settings > Privacy & Security > Accessibility, which is otherwise
    /// awkward to produce for a bare executable.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
