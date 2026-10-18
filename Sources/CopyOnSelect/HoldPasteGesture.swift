import Foundation

/// Pure gesture decisions; no event injection, AX calls, or clipboard access.
/// The host receives its original down and a matching up at the original caret.
struct HoldPasteGesture {
    enum Phase: Equatable { case idle, waiting, showing, cancelling }
    enum Release: Equatable { case ordinary, cancel(CGPoint), paste(CGPoint) }
    private(set) var phase: Phase = .idle
    private(set) var origin: CGPoint = .zero
    private(set) var token = 0
    private(set) var button: CGRect = .zero
    let tolerance: CGFloat = 6

    mutating func begin(at point: CGPoint, eligible: Bool) {
        token += 1
        origin = point
        phase = eligible ? .waiting : .idle
    }

    /// Once a drag has left the tolerance, returning to the start cannot arm it.
    mutating func move(to point: CGPoint) -> Bool {
        if phase == .waiting, hypot(point.x - origin.x, point.y - origin.y) > tolerance {
            cancel()
        }
        return phase == .showing || phase == .cancelling
    }

    mutating func show(_ frame: CGRect, token expected: Int) -> Bool {
        guard token == expected, phase == .waiting, !frame.contains(origin) else { return false }
        button = frame
        phase = .showing
        return true
    }

    mutating func cancel() {
        token += 1
        // Keep swallowing this drag until its matching up. The host still
        // needs that up at the original location, even if the menu disappears.
        phase = phase == .showing || phase == .cancelling ? .cancelling : .idle
    }

    mutating func release(at point: CGPoint, allowed: Bool) -> Release {
        let previous = phase
        phase = .idle
        token += 1
        guard previous == .showing || previous == .cancelling else { return .ordinary }
        return previous == .showing && allowed && button.contains(point)
            ? .paste(origin) : .cancel(origin)
    }
}
