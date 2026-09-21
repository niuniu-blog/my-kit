import CoreGraphics
import Testing
@testable import Core

@Suite struct ModifierEventTranslatorTests {
    private let leftOption: Int64 = 58
    private let rightOption: Int64 = 61
    private let leftCommand: Int64 = 55

    @Test func optionPressedAlone() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate])
        #expect(event == .targetDown(otherModifiersHeld: false))
    }

    @Test func rightOptionCountsToo() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: rightOption, flags: [.maskAlternate])
        #expect(event == .targetDown(otherModifiersHeld: false))
    }

    @Test func optionPressedWhileCommandHeld() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate, .maskCommand])
        #expect(event == .targetDown(otherModifiersHeld: true))
    }

    @Test func capsLockDoesNotCountAsOtherModifier() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate, .maskAlphaShift])
        #expect(event == .targetDown(otherModifiersHeld: false))
    }

    @Test func optionReleased() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [])
        #expect(event == .targetUp)
    }

    @Test func otherModifierChangeIsOtherInput() {
        let event = ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftCommand, flags: [.maskCommand])
        #expect(event == .otherInput)
    }

    @Test func keyDownIsOtherInput() {
        let event = ModifierEventTranslator.translate(type: .keyDown, keyCode: 0, flags: [])
        #expect(event == .otherInput)
    }

    @Test func unrelatedEventTypesAreIgnored() {
        #expect(ModifierEventTranslator.translate(type: .keyUp, keyCode: 0, flags: []) == nil)
        #expect(ModifierEventTranslator.translate(type: .tapDisabledByTimeout, keyCode: 0, flags: []) == nil)
    }
}
