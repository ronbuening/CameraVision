import AISidecarCore

/// Shared display helpers for the model-tuning controls that appear in both
/// the Settings sheet and Wizard Step 3's advanced options. Both surfaces
/// write the same config.json keys (`profile`, `model_context_window`), so
/// their choice lists and labels must not diverge.
enum ModelTuning {
    /// `ModelRunOptions` remains one provenance shape; descriptors only decide which controls are visible.
    static func supports(_ knob: ModelTuningKnob, in supportedKnobs: Set<ModelTuningKnob>) -> Bool {
        supportedKnobs.contains(knob)
    }

    /// Built-in rendering profiles ordered by the image size sent to the model.
    static let profileNamesBySize: [String] = ModelInputProfileRegistry.profiles
        .sorted { $0.maxLongEdge < $1.maxLongEdge }
        .map(\.name)

    /// Ollama `num_ctx` choices offered in the GUI. config.json accepts any
    /// non-negative value; these cover local vision models up to 256k windows.
    /// Larger windows grow the KV cache, so memory use rises with the choice.
    /// 0 is the "Default" sentinel: no num_ctx is sent and Ollama sizes the
    /// window itself.
    static let contextWindowChoices: [Int] = [0, 2_048, 4_096, 8_192, 16_384, 32_768, 65_536, 131_072, 262_144]

    static func contextWindowLabel(_ tokens: Int) -> String {
        tokens == 0 ? "Default" : "\(tokens)"
    }

    /// Display a profile by the long-edge pixel size it renders, since that is
    /// the property users pick it for.
    static func imageSizeLabel(forProfileNamed name: String) -> String {
        guard let profile = ModelInputProfileRegistry.profiles.first(where: { $0.name == name }) else {
            return name
        }
        return "\(profile.maxLongEdge) px"
    }
}
