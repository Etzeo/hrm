import CoreGraphics
import Foundation

final class EventTapManager: TapHoldEngineDelegate {
    private struct ActiveModifierAssignment {
        let modifier: Modifier
        let flagsChangedKeyCode: UInt16
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private let configurationLock = NSLock()
    private var workerRunLoop: CFRunLoop?
    private var requestedConfiguration: Configuration?
    private var engine: TapHoldEngine
    private let synthesizer: any EventSynthesizing
    private var currentModifierFlags: CGEventFlags = []
    private var activeModifierAssignments: [UInt16: ActiveModifierAssignment] = [:]
    /// Key codes currently being suppressed by the engine (undecided/hold).
    /// Used by the callback to skip auto-repeat events without entering the engine.
    private(set) var suppressedKeyCodes: Set<UInt16> = []

    private(set) var isRunning = false

    init(engine: TapHoldEngine, synthesizer: any EventSynthesizing = EventSynthesizer()) {
        self.engine = engine
        self.synthesizer = synthesizer
        engine.delegate = self
    }

    func start() {
        guard !isRunning else { return }

        tapThread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        tapThread?.name = "com.hrm.eventtap"
        tapThread?.qualityOfService = .userInteractive
        tapThread?.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource, let tap = eventTap {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func reenable() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func requestConfigurationUpdate(_ configuration: Configuration) {
        configurationLock.lock()
        requestedConfiguration = configuration
        let runLoop = workerRunLoop
        configurationLock.unlock()

        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes!.rawValue as CFString) { [weak self] in
            self?.applyRequestedConfiguration()
        }
        CFRunLoopWakeUp(runLoop)
    }

    // MARK: - Event Processing (called from C callback)

    func processEvent(
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let timestamp = ProcessInfo.processInfo.systemUptime

        if type == .keyDown {
            if engine.isEnabled, event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                && suppressedKeyCodes.contains(keyCode)
            {
                return nil
            }
        } else if type == .keyUp {
        } else {
            // flagsChanged — pass through
            return Unmanaged.passUnretained(event)
        }

        let result: TapHoldEngine.EventResult
        if type == .keyDown {
            result = engine.handleKeyDown(keyCode: keyCode, event: event, timestamp: timestamp)
        } else {
            result = engine.handleKeyUp(keyCode: keyCode, event: event, timestamp: timestamp)
        }

        switch result {
        case .passThrough:
            suppressedKeyCodes.remove(keyCode)
            if !currentModifierFlags.isEmpty {
                event.flags = event.flags.union(currentModifierFlags)
            }
            return Unmanaged.passUnretained(event)
        case .suppress:
            if type == .keyDown {
                suppressedKeyCodes.insert(keyCode)
            } else if type == .keyUp {
                suppressedKeyCodes.remove(keyCode)
            }
            return nil
        }
    }

    // MARK: - TapHoldEngineDelegate

    func engineDidResolveHold(binding: KeyBinding) {
        guard let modifier = binding.modifier else { return }
        let flagKeyCode = binding.position.hand == .left
            ? modifier.leftFlagsChanged
            : modifier.rightFlagsChanged

        guard activeModifierAssignments[binding.keyCode] == nil else { return }
        activeModifierAssignments[binding.keyCode] = ActiveModifierAssignment(
            modifier: modifier,
            flagsChangedKeyCode: flagKeyCode
        )
        updateSyntheticModifierFlags()
        synthesizer.postFlagsChanged(keyCode: flagKeyCode, flags: currentModifierFlags)
    }

    func engineDidResolveHoldRelease(binding: KeyBinding) {
        guard let assignment = activeModifierAssignments.removeValue(forKey: binding.keyCode) else {
            return
        }
        updateSyntheticModifierFlags()
        synthesizer.postFlagsChanged(
            keyCode: assignment.flagsChangedKeyCode,
            flags: currentModifierFlags
        )
    }

    func engineDidResolveTap(binding: KeyBinding) {
        synthesizer.postKeyDown(keyCode: binding.keyCode, flags: currentModifierFlags)
        synthesizer.postKeyUp(keyCode: binding.keyCode, flags: currentModifierFlags)
    }

    func engineShouldFlushBufferedEvents(_ events: [BufferedEvent]) {
        for buffered in events {
            // Apply current modifier flags to buffered events
            if !currentModifierFlags.isEmpty {
                buffered.event.flags = buffered.event.flags.union(currentModifierFlags)
            }
            synthesizer.postEvent(buffered.event)
        }
    }

    // MARK: - Private

    private func applyRequestedConfiguration() {
        configurationLock.lock()
        let configuration = requestedConfiguration
        requestedConfiguration = nil
        configurationLock.unlock()

        if let configuration {
            engine.updateConfig(configuration)
        }
    }

    private func updateSyntheticModifierFlags() {
        currentModifierFlags = activeModifierAssignments.values.reduce(into: []) { flags, assignment in
            flags.formUnion(assignment.modifier.flag)
        }
        engine.syntheticModifierFlags = currentModifierFlags
    }

    private func runEventTapLoop() {
        let runLoop = CFRunLoopGetCurrent()
        configurationLock.lock()
        workerRunLoop = runLoop
        configurationLock.unlock()
        applyRequestedConfiguration()

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("HRM: Failed to create event tap. Check Accessibility permissions.")
            return
        }

        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else { return }

        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRunning = true
        CFRunLoopRun()

        configurationLock.lock()
        workerRunLoop = nil
        configurationLock.unlock()
    }
}
