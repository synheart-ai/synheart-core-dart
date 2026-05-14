/// V1 persona spec. Persona is owned by `syni-core-spec/personas/` and will
/// be loaded as a bundled asset once that repo ships content. For V1 we
/// declare personas as Dart constants.
library;

/// A declarative persona — voice, goals, boundaries, output schema.
class SyniPersona {
  const SyniPersona({
    required this.id,
    required this.displayName,
    required this.systemPrompt,
    required this.responseSchemaId,
    this.tone = 'calm',
  });

  /// Stable identifier (e.g. `focus-coach.v1`). Must match the value the
  /// runtime expects when conditioning prompts.
  final String id;

  /// Human-readable name surfaced in UI.
  final String displayName;

  /// One- or two-sentence tone descriptor.
  final String tone;

  /// System prompt prepended to the HSI-conditioned prompt by the runtime's
  /// `PromptBuilder`.
  final String systemPrompt;

  /// Output schema ID — must match one of `syni-runtime/schemas/*.schema.json`
  /// (`chat_response`, `coach_response`, `suggestions`).
  final String responseSchemaId;
}

/// V1 built-in personas. To be replaced with `syni-core-spec/personas/prod/`
/// bundled assets once that repo seeds content.
class SyniPersonas {
  SyniPersonas._();

  static const SyniPersona focusCoach = SyniPersona(
    id: 'focus-coach.v1',
    displayName: 'Focus Coach',
    tone: 'warm, concise, lightly structured',
    systemPrompt:
        'You are a focus coach. Help the user choose one tiny next action. '
        'Be warm, non-shaming, and concrete. Ask at most one clarifying '
        'question before proposing a 3-step plan with a first step under '
        '2 minutes. Never diagnose, never moralize, never use absolute '
        'language (always/never). Honor the user\'s current state '
        '(focus, fatigue, stress) as estimates — not facts.',
    responseSchemaId: 'coach_response',
  );

  /// Look up by ID. Returns null if unknown.
  static SyniPersona? byId(String id) {
    switch (id) {
      case 'focus-coach.v1':
        return focusCoach;
      default:
        return null;
    }
  }
}
