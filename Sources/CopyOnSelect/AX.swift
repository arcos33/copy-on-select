import ApplicationServices
import Foundation

/// Thin wrappers over the Accessibility API.
///
/// Every call here is cross-process IPC and can block, so nothing in this file
/// may be called from the event-tap callback. See Engine.
enum AX {
    /// One hung app must not wedge the worker queue.
    static let messagingTimeout: Float = 0.25

    /// Roles worth *asking* for a selection. Deliberately broad: browsers and
    /// PDF views hit-test to a deep leaf (a link, a heading, a cell) while the
    /// selection itself lives on an ancestor, so we walk up from whatever we
    /// land on.
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

    enum SelectionOutcome {
        /// A selection was read.
        case text(String)
        /// A password field was encountered; abort everything, copy nothing.
        case secure
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
        var current: AXUIElement? = element
        var depth = 0

        while let node = current, depth < maxDepth {
            // Checked at every level: a secure field anywhere on the path means
            // stop entirely rather than continue up to a readable ancestor.
            if isSecure(node) { return .secure }

            if isReadableRole(node) {
                let range = selectedRange(node)

                if let range, range.length > maxCharacters { return .none }

                if let text = selectedText(node), !text.isEmpty {
                    return text.count <= maxCharacters ? .text(text) : .none
                }
                if let range, range.length > 0, let text = string(node, forRange: range),
                    !text.isEmpty
                {
                    return .text(text)
                }
            }

            current = parent(node)
            depth += 1
        }
        return .none
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
