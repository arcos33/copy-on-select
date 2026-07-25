import CoreGraphics
import Foundation

/// A listen-only tap on left mouse down/up.
///
/// Deliberately NOT tapping .flagsChanged: that is a keyboard event type, which
/// would make this binary keylogger-shaped to anyone auditing it, and Secure
/// Input Mode suppresses those events anyway. Modifier state is read on demand
/// via CGEventSource.flagsState instead.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> Void

    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var isActive: Bool {
        guard let port else { return false }
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// Returns false when the tap could not be created, which in practice means
    /// accessibility trust has not been granted yet.
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()

            // The kernel disables a tap that takes too long, or on certain user
            // input events. Without re-enabling, the app silently stops working
            // after the first stall.
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                tap.reenable()
                return Unmanaged.passUnretained(event)
            }

            tap.handler(type, event)
            return Unmanaged.passUnretained(event)
        }

        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            return false
        }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    /// Pausing genuinely stops observation rather than filtering afterwards.
    func setEnabled(_ enabled: Bool) {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: enabled)
    }

    func stop() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        port = nil
        source = nil
    }

    /// The run loop holds the source, which holds a mach port carrying an
    /// UNRETAINED pointer to self. Tearing the source down here keeps that
    /// pointer from outliving the object.
    deinit {
        stop()
    }

    private func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }
}
