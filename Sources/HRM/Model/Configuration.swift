struct Configuration: Codable, Equatable {
    var enabled: Bool
    var quickTapTermMs: Int
    var requirePriorIdleMs: Int
    var ignoreSpacebarForShiftModifiers: Bool
    var bilateralFiltering: Bool
    var holdTriggerOnRelease: Bool
    var keyBindings: [KeyBinding]

    private enum CodingKeys: String, CodingKey {
        case enabled, quickTapTermMs, requirePriorIdleMs
        case ignoreSpacebarForShiftModifiers
        case bilateralFiltering, holdTriggerOnRelease, keyBindings
    }

    init(
        enabled: Bool,
        quickTapTermMs: Int,
        requirePriorIdleMs: Int,
        ignoreSpacebarForShiftModifiers: Bool,
        bilateralFiltering: Bool,
        holdTriggerOnRelease: Bool,
        keyBindings: [KeyBinding]
    ) {
        self.enabled = enabled
        self.quickTapTermMs = quickTapTermMs
        self.requirePriorIdleMs = requirePriorIdleMs
        self.ignoreSpacebarForShiftModifiers = ignoreSpacebarForShiftModifiers
        self.bilateralFiltering = bilateralFiltering
        self.holdTriggerOnRelease = holdTriggerOnRelease
        self.keyBindings = keyBindings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        quickTapTermMs = try container.decode(Int.self, forKey: .quickTapTermMs)
        requirePriorIdleMs = try container.decode(Int.self, forKey: .requirePriorIdleMs)
        ignoreSpacebarForShiftModifiers = try container.decodeIfPresent(
            Bool.self,
            forKey: .ignoreSpacebarForShiftModifiers
        ) ?? true
        bilateralFiltering = try container.decode(Bool.self, forKey: .bilateralFiltering)
        holdTriggerOnRelease = try container.decode(Bool.self, forKey: .holdTriggerOnRelease)
        keyBindings = try container.decode([KeyBinding].self, forKey: .keyBindings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(quickTapTermMs, forKey: .quickTapTermMs)
        try container.encode(requirePriorIdleMs, forKey: .requirePriorIdleMs)
        try container.encode(ignoreSpacebarForShiftModifiers, forKey: .ignoreSpacebarForShiftModifiers)
        try container.encode(bilateralFiltering, forKey: .bilateralFiltering)
        try container.encode(holdTriggerOnRelease, forKey: .holdTriggerOnRelease)
        try container.encode(keyBindings, forKey: .keyBindings)
    }

    func effectiveQuickTapTerm(for binding: KeyBinding) -> Int {
        binding.quickTapTermMs ?? quickTapTermMs
    }

    func effectiveRequirePriorIdle(for binding: KeyBinding) -> Int {
        binding.requirePriorIdleMs ?? requirePriorIdleMs
    }

    func effectiveBilateralFiltering(for binding: KeyBinding) -> Bool {
        binding.bilateralFiltering ?? bilateralFiltering
    }

    func binding(for keyCode: UInt16) -> KeyBinding? {
        keyBindings.first { $0.keyCode == keyCode && $0.enabled }
    }
}
