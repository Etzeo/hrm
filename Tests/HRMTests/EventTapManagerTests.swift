import CoreGraphics
import Testing
@testable import HRM

private struct FlagsChangedEvent: Equatable {
    let keyCode: UInt16
    let flags: CGEventFlags
}

private final class RecordingEventSynthesizer: EventSynthesizing {
    private(set) var flagsChangedEvents: [FlagsChangedEvent] = []

    func postKeyDown(keyCode: UInt16, flags: CGEventFlags) {}

    func postKeyUp(keyCode: UInt16, flags: CGEventFlags) {}

    func postFlagsChanged(keyCode: UInt16, flags: CGEventFlags) {
        flagsChangedEvents.append(FlagsChangedEvent(keyCode: keyCode, flags: flags))
    }

    func postEvent(_: CGEvent) {}
}

@Suite("EventTapManager Tests")
struct EventTapManagerTests {
    @Test("Shift remains active until every HRM Shift key releases")
    func duplicateShiftLifetime() {
        let config = DefaultConfiguration.make()
        let engine = TapHoldEngine(config: config)
        let synthesizer = RecordingEventSynthesizer()
        let manager = EventTapManager(engine: engine, synthesizer: synthesizer)
        let f = config.keyBindings.first { $0.keyCode == 0x03 }!
        let j = config.keyBindings.first { $0.keyCode == 0x26 }!

        manager.engineDidResolveHold(binding: f)
        manager.engineDidResolveHold(binding: j)
        manager.engineDidResolveHoldRelease(binding: f)

        #expect(engine.syntheticModifierFlags == .maskShift)

        manager.engineDidResolveHoldRelease(binding: j)

        #expect(engine.syntheticModifierFlags.isEmpty)
        #expect(synthesizer.flagsChangedEvents == [
            FlagsChangedEvent(keyCode: 0x38, flags: .maskShift),
            FlagsChangedEvent(keyCode: 0x3C, flags: .maskShift),
            FlagsChangedEvent(keyCode: 0x38, flags: .maskShift),
            FlagsChangedEvent(keyCode: 0x3C, flags: []),
        ])
    }

    @Test("Releasing one modifier preserves different active modifier")
    func mixedModifierLifetime() {
        let config = DefaultConfiguration.make()
        let engine = TapHoldEngine(config: config)
        let synthesizer = RecordingEventSynthesizer()
        let manager = EventTapManager(engine: engine, synthesizer: synthesizer)
        let f = config.keyBindings.first { $0.keyCode == 0x03 }!
        let k = config.keyBindings.first { $0.keyCode == 0x28 }!

        manager.engineDidResolveHold(binding: f)
        manager.engineDidResolveHold(binding: k)
        manager.engineDidResolveHoldRelease(binding: f)
        manager.engineDidResolveHoldRelease(binding: k)

        #expect(synthesizer.flagsChangedEvents == [
            FlagsChangedEvent(keyCode: 0x38, flags: .maskShift),
            FlagsChangedEvent(keyCode: 0x36, flags: [.maskShift, .maskCommand]),
            FlagsChangedEvent(keyCode: 0x38, flags: .maskCommand),
            FlagsChangedEvent(keyCode: 0x36, flags: []),
        ])
    }
}
