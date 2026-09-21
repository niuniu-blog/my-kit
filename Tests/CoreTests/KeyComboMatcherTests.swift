import CoreGraphics
import Testing
@testable import Core

@Suite struct KeyComboMatcherTests {
    private let combo = KeyCombo.controlCommandA
    private let aKey: Int64 = 0

    @Test func controlCommandAIsKeyCodeZeroWithControlAndCommand() {
        #expect(combo.keyCode == 0)
        #expect(combo.modifiers == [.maskControl, .maskCommand])
    }

    @Test func matchesExactCombo() {
        #expect(KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskControl, .maskCommand]))
    }

    @Test func ignoresIrrelevantFlagsLikeCapsLockAndFn() {
        let flags: CGEventFlags = [.maskControl, .maskCommand, .maskAlphaShift, .maskSecondaryFn, .maskNonCoalesced]
        #expect(KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: flags))
    }

    @Test func doesNotMatchWithExtraModifier() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskControl, .maskCommand, .maskShift]))
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskControl, .maskCommand, .maskAlternate]))
    }

    @Test func doesNotMatchWithMissingModifier() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: [.maskCommand]))
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: aKey, flags: []))
    }

    @Test func doesNotMatchOtherKeys() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyDown, keyCode: 1, flags: [.maskControl, .maskCommand]))
    }

    @Test func onlyMatchesKeyDown() {
        #expect(!KeyComboMatcher.matches(combo, type: .keyUp, keyCode: aKey, flags: [.maskControl, .maskCommand]))
        #expect(!KeyComboMatcher.matches(combo, type: .flagsChanged, keyCode: aKey, flags: [.maskControl, .maskCommand]))
    }
}
