import AppKit
import CoreGraphics
import Testing
@testable import Core

@Suite struct HotkeySettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "mykit-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func screenshotDefaultsToShiftCommandA() {
        let settings = HotkeySettings(defaults: makeDefaults())
        #expect(settings.screenshotCombo == KeyCombo.shiftCommandA)
        #expect(settings.screenshotKeyLabel == "A")
        #expect(settings.screenshotDisplay == "⇧⌘A")
    }

    @Test func storesCustomScreenshotHotkey() {
        let defaults = makeDefaults()
        let combo = KeyCombo(keyCode: 1, modifiers: [.maskControl, .maskAlternate])
        HotkeySettings(defaults: defaults).setScreenshot(combo: combo, keyLabel: "S")

        let reread = HotkeySettings(defaults: defaults)
        #expect(reread.screenshotCombo == combo)
        #expect(reread.screenshotKeyLabel == "S")
        #expect(reread.screenshotDisplay == "⌃⌥S")
    }

    @Test func resetRestoresDefault() {
        let defaults = makeDefaults()
        let settings = HotkeySettings(defaults: defaults)
        settings.setScreenshot(combo: KeyCombo(keyCode: 122, modifiers: []), keyLabel: "F1")
        settings.resetScreenshot()
        #expect(settings.screenshotCombo == KeyCombo.shiftCommandA)
        #expect(settings.screenshotDisplay == "⇧⌘A")
    }

    @Test func storedModifiersAreMaskedToTheFourRelevantOnes() {
        let defaults = makeDefaults()
        let noisy: CGEventFlags = [.maskCommand, .maskAlphaShift, .maskNonCoalesced]
        HotkeySettings(defaults: defaults).setScreenshot(combo: KeyCombo(keyCode: 0, modifiers: noisy), keyLabel: "A")
        #expect(HotkeySettings(defaults: defaults).screenshotCombo.modifiers == [.maskCommand])
    }

    @Test func clipboardDoubleTapDefaultsToOptionAndRoundTrips() {
        let defaults = makeDefaults()
        #expect(HotkeySettings(defaults: defaults).clipboardDoubleTap == .option)
        HotkeySettings(defaults: defaults).clipboardDoubleTap = .control
        #expect(HotkeySettings(defaults: defaults).clipboardDoubleTap == .control)
    }

    @Test func unknownStoredDoubleTapFallsBackToOption() {
        let defaults = makeDefaults()
        defaults.set("hyper", forKey: HotkeySettings.clipboardDoubleTapKey)
        #expect(HotkeySettings(defaults: defaults).clipboardDoubleTap == .option)
    }

    @Test func changesPostNotification() {
        let defaults = makeDefaults()
        let settings = HotkeySettings(defaults: defaults)
        var count = 0
        // 通知的 object 是对应的 UserDefaults；按它过滤，并行运行的其他测试不会干扰计数
        let token = NotificationCenter.default.addObserver(
            forName: HotkeySettings.didChangeNotification, object: defaults, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        settings.setScreenshot(combo: KeyCombo(keyCode: 1, modifiers: [.maskCommand, .maskShift]), keyLabel: "S")
        settings.clipboardDoubleTap = .command
        settings.resetScreenshot()

        #expect(count == 3)
    }
}

@Suite struct KeyComboDisplayTests {
    @Test func modifiersAreShownInStandardMacOrder() {
        let all: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        #expect(KeyCombo(keyCode: 0, modifiers: all).displayString(keyLabel: "A") == "⌃⌥⇧⌘A")
        #expect(KeyCombo(keyCode: 122, modifiers: []).displayString(keyLabel: "F1") == "F1")
    }

    @Test func convertsAppKitModifierFlags() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function]
        #expect(KeyCombo.modifiers(from: flags) == [.maskCommand, .maskShift])
        #expect(KeyCombo.modifiers(from: [.control, .option]) == [.maskControl, .maskAlternate])
    }

    @Test func convertsBackToAppKitModifierFlags() {
        let combo = KeyCombo(keyCode: 0, modifiers: [.maskShift, .maskCommand])
        #expect(combo.appKitModifiers == [.shift, .command])
    }

    @Test func keyLabels() {
        #expect(KeyLabel.label(keyCode: 0, characters: "a") == "A")
        #expect(KeyLabel.label(keyCode: 122, characters: nil) == "F1")
        #expect(KeyLabel.label(keyCode: 111, characters: nil) == "F12")
        #expect(KeyLabel.label(keyCode: 49, characters: " ") == "Space")
        #expect(KeyLabel.label(keyCode: 18, characters: "1") == "1")
        #expect(KeyLabel.label(keyCode: 200, characters: nil) == "键 200")
    }
}

@Suite struct HotkeyValidatorTests {
    @Test func plainOrShiftOnlyLettersNeedARealModifier() {
        #expect(HotkeyValidator.validate(keyCode: 0, modifiers: []) == .needsModifier)
        #expect(HotkeyValidator.validate(keyCode: 0, modifiers: [.maskShift]) == .needsModifier)
    }

    @Test func functionKeysMayBeUsedAlone() {
        #expect(HotkeyValidator.validate(keyCode: 122, modifiers: []) == .ok)      // F1，Snipaste 的习惯
    }

    @Test func normalCombosAreAccepted() {
        #expect(HotkeyValidator.validate(keyCode: 0, modifiers: [.maskShift, .maskCommand]) == .ok)
        #expect(HotkeyValidator.validate(keyCode: 0, modifiers: [.maskControl, .maskCommand]) == .ok)
        #expect(HotkeyValidator.validate(keyCode: 1, modifiers: [.maskAlternate]) == .ok)
    }

    @Test func essentialSystemShortcutsAreReserved() {
        #expect(HotkeyValidator.validate(keyCode: 8, modifiers: [.maskCommand]) == .reserved)    // ⌘C
        #expect(HotkeyValidator.validate(keyCode: 9, modifiers: [.maskCommand]) == .reserved)    // ⌘V
        #expect(HotkeyValidator.validate(keyCode: 12, modifiers: [.maskCommand]) == .reserved)   // ⌘Q
        #expect(HotkeyValidator.validate(keyCode: 49, modifiers: [.maskCommand]) == .reserved)   // ⌘Space
        #expect(HotkeyValidator.validate(keyCode: 48, modifiers: [.maskCommand]) == .reserved)   // ⌘Tab
    }

    @Test func sameLetterWithMoreModifiersIsNotReserved() {
        #expect(HotkeyValidator.validate(keyCode: 8, modifiers: [.maskCommand, .maskControl]) == .ok)
    }
}

@Suite struct DoubleTapModifierTests {
    @Test func translatorHonoursTheChosenModifier() {
        let leftControl: Int64 = 59
        let leftOption: Int64 = 58
        #expect(ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftControl, flags: [.maskControl], target: .control)
            == .targetDown(otherModifiersHeld: false))
        #expect(ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftControl, flags: [], target: .control)
            == .targetUp)
        #expect(ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftOption, flags: [.maskAlternate], target: .control)
            == .otherInput)
        #expect(ModifierEventTranslator.translate(type: .flagsChanged, keyCode: leftControl, flags: [.maskControl, .maskAlternate], target: .control)
            == .targetDown(otherModifiersHeld: true))
    }

    @Test func commandTarget() {
        let rightCommand: Int64 = 54
        #expect(ModifierEventTranslator.translate(type: .flagsChanged, keyCode: rightCommand, flags: [.maskCommand], target: .command)
            == .targetDown(otherModifiersHeld: false))
    }

    @Test func defaultTargetIsStillOption() {
        #expect(ModifierEventTranslator.translate(type: .flagsChanged, keyCode: 58, flags: [.maskAlternate])
            == .targetDown(otherModifiersHeld: false))
    }

    @Test func displayNamesAreChinese() {
        #expect(DoubleTapModifier.option.displayName == "双击 Option (⌥)")
        #expect(DoubleTapModifier.control.displayName == "双击 Control (⌃)")
        #expect(DoubleTapModifier.command.displayName == "双击 Command (⌘)")
        #expect(DoubleTapModifier.allCases.count == 3)      // 不提供 Shift：中文输入法用它切换中英文
    }
}

@MainActor
@Suite struct HotkeyRecorderModelTests {
    private final class Box {
        var combo = KeyCombo.shiftCommandA
        var label = "A"
        var resets = 0
    }

    private func makeModel(_ box: Box) -> HotkeyRecorderModel {
        HotkeyRecorderModel(
            current: { (combo: box.combo, keyLabel: box.label) },
            save: { combo, label in box.combo = combo; box.label = label },
            resetToDefault: { box.combo = KeyCombo.shiftCommandA; box.label = "A"; box.resets += 1 }
        )
    }

    @Test func showsCurrentHotkey() {
        let model = makeModel(Box())
        #expect(model.display == "⇧⌘A")
        #expect(!model.isRecording)
    }

    @Test func validKeySavesAndStopsRecording() {
        let box = Box()
        let model = makeModel(box)
        model.beginRecording(installMonitor: false)
        model.handleKey(keyCode: 1, modifiers: [.control, .option], characters: "s")

        #expect(box.combo == KeyCombo(keyCode: 1, modifiers: [.maskControl, .maskAlternate]))
        #expect(box.label == "S")
        #expect(model.display == "⌃⌥S")
        #expect(!model.isRecording)
        #expect(model.message == nil)
    }

    @Test func invalidKeyShowsMessageAndKeepsRecording() {
        let box = Box()
        let model = makeModel(box)
        model.beginRecording(installMonitor: false)
        model.handleKey(keyCode: 0, modifiers: [], characters: "a")

        #expect(model.isRecording)
        #expect(model.message == "需要同时按住 ⌘、⌃ 或 ⌥（F1–F12 可以单独使用）")
        #expect(box.combo == KeyCombo.shiftCommandA)

        model.handleKey(keyCode: 8, modifiers: [.command], characters: "c")
        #expect(model.message == "这是系统常用快捷键，换一个吧")
    }

    @Test func escapeCancelsWithoutSaving() {
        let box = Box()
        let model = makeModel(box)
        model.beginRecording(installMonitor: false)
        model.handleKey(keyCode: 53, modifiers: [], characters: "\u{1b}")

        #expect(!model.isRecording)
        #expect(box.combo == KeyCombo.shiftCommandA)
    }

    @Test func keysAreIgnoredWhenNotRecording() {
        let box = Box()
        let model = makeModel(box)
        model.handleKey(keyCode: 1, modifiers: [.command, .shift], characters: "s")
        #expect(box.combo == KeyCombo.shiftCommandA)
    }

    @Test func resetRestoresDefaultAndUpdatesDisplay() {
        let box = Box()
        box.combo = KeyCombo(keyCode: 122, modifiers: [])
        box.label = "F1"
        let model = makeModel(box)
        #expect(model.display == "F1")

        model.reset()

        #expect(box.resets == 1)
        #expect(model.display == "⇧⌘A")
    }

    @Test func recordingPostsBeginAndEndNotifications() {
        let model = makeModel(Box())
        var events: [String] = []
        let begin = NotificationCenter.default.addObserver(forName: HotkeySettings.recordingDidBeginNotification, object: model, queue: nil) { _ in events.append("begin") }
        let end = NotificationCenter.default.addObserver(forName: HotkeySettings.recordingDidEndNotification, object: model, queue: nil) { _ in events.append("end") }
        defer {
            NotificationCenter.default.removeObserver(begin)
            NotificationCenter.default.removeObserver(end)
        }

        model.beginRecording(installMonitor: false)
        model.cancelRecording()

        #expect(events == ["begin", "end"])
    }
}
