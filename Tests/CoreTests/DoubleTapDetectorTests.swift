import Foundation
import Testing
@testable import Core

@Suite struct DoubleTapDetectorTests {
    private typealias Event = DoubleTapDetector.Event
    private let down = Event.targetDown(otherModifiersHeld: false)
    private let downWithOthers = Event.targetDown(otherModifiersHeld: true)

    private func run(_ events: [(Event, TimeInterval)]) -> [Bool] {
        var detector = DoubleTapDetector()
        var results: [Bool] = []
        for (event, time) in events {
            results.append(detector.handle(event, at: time))
        }
        return results
    }

    @Test func triggersOnSecondPress() {
        #expect(run([(down, 0.00), (.targetUp, 0.08), (down, 0.20)]) == [false, false, true])
    }

    @Test func doesNotTriggerWhenGapTooLong() {
        #expect(run([(down, 0.00), (.targetUp, 0.08), (down, 0.39)]) == [false, false, false])
    }

    @Test func lateSecondPressCountsAsNewFirstTap() {
        let results = run([(down, 0.00), (.targetUp, 0.08), (down, 0.50), (.targetUp, 0.55), (down, 0.65)])
        #expect(results == [false, false, false, false, true])
    }

    @Test func doesNotTriggerWhenFirstHoldTooLong() {
        #expect(run([(down, 0.00), (.targetUp, 0.35), (down, 0.40)]) == [false, false, false])
    }

    @Test func otherKeyBetweenTapsResets() {
        #expect(run([(down, 0.00), (.targetUp, 0.05), (.otherInput, 0.10), (down, 0.15)]) == [false, false, false, false])
    }

    @Test func otherKeyDuringFirstHoldResets() {
        // Option+字母 输入特殊字符
        #expect(run([(down, 0.00), (.otherInput, 0.03), (.targetUp, 0.06), (down, 0.10)]) == [false, false, false, false])
    }

    @Test func otherModifierHeldOnFirstPressIsIgnored() {
        #expect(run([(downWithOthers, 0.00), (.targetUp, 0.05), (down, 0.10)]) == [false, false, false])
    }

    @Test func otherModifierHeldOnSecondPressDoesNotTrigger() {
        #expect(run([(down, 0.00), (.targetUp, 0.05), (downWithOthers, 0.10)]) == [false, false, false])
    }

    @Test func secondOptionKeyPressedWhileFirstHeldResets() {
        #expect(run([(down, 0.00), (down, 0.05), (.targetUp, 0.08), (down, 0.12)]) == [false, false, false, false])
    }

    @Test func resetsAfterTriggerAndCanTriggerAgain() {
        let results = run([
            (down, 0.00), (.targetUp, 0.05), (down, 0.10),      // 第一次双击
            (.targetUp, 0.15),
            (down, 0.20), (.targetUp, 0.25), (down, 0.30),      // 第二次双击
        ])
        #expect(results == [false, false, true, false, false, false, true])
    }

    @Test func thresholdsAreConfigurable() {
        var detector = DoubleTapDetector()
        detector.maxGap = 0.5
        _ = detector.handle(down, at: 0.0)
        _ = detector.handle(.targetUp, at: 0.05)
        #expect(detector.handle(down, at: 0.50) == true)
    }
}
