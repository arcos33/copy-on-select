import ApplicationServices
import Foundation

/// Thin wrappers over the Accessibility API.
///
/// Every call here is cross-process IPC and can block, so nothing in this file
/// may be called from the event-tap callback. See Engine.
enum AX {
    /// One hung app must not wedge the worker queue.
    static let messagingTimeout: Float = 0.25

    /// Roles that can legitimately hold a text selection. Used to gate the
    /// Cmd+C fallback: if the element under the cursor is not one of these, we
    /// do nothing rather than guess.
    static let textRoles: Set<String> = [
        kAXTextAreaRole as String,
        kAXTextFieldRole as String,
        kAXStaticTextRole as String,
        kAXComboBoxRole as String,
        "AXWebArea",
    ]

    /// Password fields. Secure Input Mode does NOT protect the accessibility
    /// path — it only suppresses keyboard taps and synthetic keystrokes — so
    /// this check is the actual protection.
    static let secureRoles: Set<String> = [
        "AXSecureTextField",
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

    /// True when this element is a password field, by role or subrole. Web
    /// password inputs surface as a text field with a secure subrole rather
    /// than a secure role, so both must be checked.
    static func isSecure(_ element: AXUIElement) -> Bool {
        if let role = role(element), secureRoles.contains(role) { return true }
        if let subrole = subrole(element), secureRoles.contains(subrole) { return true }
        return false
    }

    static func isTextRole(_ element: AXUIElement) -> Bool {
        guard let role = role(element) else { return false }
        return textRoles.contains(role)
    }

    /// The element directly under a screen point. Point must be in top-left
    /// origin coordinates, which is what CGEvent.location already gives us.
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

    /// Rung 3 of the ladder: some apps implement the range plus the
    /// parameterized string-for-range attribute without implementing
    /// kAXSelectedText at all.
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

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompting variant. This is also what creates the entry in
    /// System Settings > Privacy & Security > Accessibility, which is otherwise
    /// awkward to produce for a non-.app executable.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
