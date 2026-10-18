import AppKit

// Runs with Command Line Tools alone; this Mac does not ship XCTest.
func expectTrue(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value(), "Expected true", file: file, line: line)
}
func expectFalse(_ value: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(!value(), "Expected false", file: file, line: line)
}
func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Expected \(rhs), got \(lhs)", file: file, line: line)
}

@main
final class HoldPasteGestureTests {
    static func main() {
        let suite = HoldPasteGestureTests()
        suite.testShortClickStaysOrdinary()
        suite.testSlideReleasePastesOnceAndBalancesMouseUpAtOriginalPoint()
        suite.testStationaryAndOutsideReleasesCancel()
        suite.testDragOutAndBackCannotBecomePaste()
        suite.testSmallPointerJitterCanStillHold()
        suite.testStaleLookupCannotOpenOnLaterClick()
        suite.testIneligibleGestureNeverActivates()
        suite.testFocusLossOrTapInterruptionCancelsButStillBalancesRelease()
        suite.testModifierOnReleasePreventsPaste()
        suite.testButtonNeverOpensUnderPointerEvenAtScreenEdges()
        print("Passed 10 gesture and placement checks")
    }

    let origin = CGPoint(x: 100, y: 100)
    let button = CGRect(x: 118, y: 76, width: 124, height: 48)

    func testShortClickStaysOrdinary() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        expectEqual(gesture.release(at: origin, allowed: true), .ordinary)
    }

    func testSlideReleasePastesOnceAndBalancesMouseUpAtOriginalPoint() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        expectTrue(gesture.show(button, token: gesture.token))
        expectTrue(gesture.move(to: CGPoint(x: 160, y: 100)))
        expectEqual(gesture.release(at: CGPoint(x: 160, y: 100), allowed: true), .paste(origin))
        expectEqual(gesture.release(at: CGPoint(x: 160, y: 100), allowed: true), .ordinary)
    }

    func testStationaryAndOutsideReleasesCancel() {
        for point in [origin, CGPoint(x: 300, y: 300)] {
            var gesture = HoldPasteGesture()
            gesture.begin(at: origin, eligible: true)
            expectTrue(gesture.show(button, token: gesture.token))
            expectEqual(gesture.release(at: point, allowed: true), .cancel(origin))
        }
    }

    func testDragOutAndBackCannotBecomePaste() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        let token = gesture.token
        expectFalse(gesture.move(to: CGPoint(x: 107, y: 100)))
        expectFalse(gesture.move(to: origin))
        expectFalse(gesture.show(button, token: token))
        expectEqual(gesture.release(at: origin, allowed: true), .ordinary)
    }

    func testSmallPointerJitterCanStillHold() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        expectFalse(gesture.move(to: CGPoint(x: 102, y: 102)))
        expectTrue(gesture.show(button, token: gesture.token))
    }

    func testStaleLookupCannotOpenOnLaterClick() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        let token = gesture.token
        _ = gesture.release(at: origin, allowed: true)
        gesture.begin(at: origin, eligible: true)
        expectFalse(gesture.show(button, token: token))
    }

    func testIneligibleGestureNeverActivates() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: false)
        expectFalse(gesture.show(button, token: gesture.token))
    }

    func testFocusLossOrTapInterruptionCancelsButStillBalancesRelease() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        expectTrue(gesture.show(button, token: gesture.token))
        gesture.cancel()
        expectTrue(gesture.move(to: CGPoint(x: 160, y: 100)))
        expectEqual(gesture.release(at: CGPoint(x: 160, y: 100), allowed: true), .cancel(origin))
    }

    func testModifierOnReleasePreventsPaste() {
        var gesture = HoldPasteGesture()
        gesture.begin(at: origin, eligible: true)
        expectTrue(gesture.show(button, token: gesture.token))
        expectEqual(gesture.release(at: CGPoint(x: 160, y: 100), allowed: false), .cancel(origin))
    }

    func testButtonNeverOpensUnderPointerEvenAtScreenEdges() {
        let screens = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                       CGRect(x: -1920, y: -1080, width: 1920, height: 1080)]
        for screen in screens {
            for point in [CGPoint(x: screen.minX + 1, y: screen.minY + 1),
                          CGPoint(x: screen.maxX - 1, y: screen.maxY - 1),
                          CGPoint(x: screen.midX, y: screen.midY)] {
                let frame = PasteButton.frame(near: point, in: screen)
                expectTrue(screen.contains(frame))
                expectFalse(frame.contains(point))
            }
        }
    }
}
