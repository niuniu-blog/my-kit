import CoreGraphics
import Testing
@testable import Core

@Suite struct KeyComboMatcherTests {
    private let combo = KeyCombo.shiftCommandA
    private let aKey: Int64 = 0

    @Test func shiftCommandAIsKeyCodeZeroWithShiftAndCommand() {
        #expect(combo.keyCode == 0)
        #expect(combo.modifiers == [.maskShift, .maskCommand])
    }

    @Test func matchesExactCombo() {
        #expect(KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskShift, .maskCommand]))
    }

    @Test func ignoresIrrelevantFlagsLikeCapsLockAndFn() {
        let flags: CGEventFlags = [.maskShift, .maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNonCoalesced]
        #expect(KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: flags))
    }

    @Test func doesNotMatchWithExtraModifier() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskShift, .maskCommand, .maskControl]))
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskShift, .maskCommand, .maskAlternate]))
    }

    @Test func doesNotMatchWithMissingModifier() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskCommand]))
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: []))
    }

    @Test func doesNotMatchOtherKeys() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: 1, flags: [.maskShift, .maskCommand]))
    }

    @Test func onlyMatchesKeyDown() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyUp, keyCode: aKey, flags: [.maskShift, .maskCommand]))
        #expect(!KeyComboMatcher.matches(combo, type: .flagsChanged, keyCode: aKey, flags: [.maskShift, .maskCommand]))
    }
}
