/// Sub-classification of a `Focus` task — symmetric to
/// [WorkoutKind] for `Movement`. Lets the host signal cognitive-load
/// grading so the engine's explanation trace can surface
/// "user just played Hard Stroop" as session context.
///
/// Mirrors `synheart_personalization_runtime::FocusKind` and the
/// `synheart_core_set_focus_kind` discriminant table:
/// `0=unknown, 1=easy, 2=medium, 3=hard`.
///
/// **Behaviour note (2026-05-01):** the engine records FocusKind on the
/// `PersonalizationContext.explanation.entries` for trace observability
/// but does not fold it into multipliers. A rule-pack
/// update can wire actual modulation without changing this enum or the
/// FFI. See `FocusKind` doc in
/// the personalization runtime in the Synheart Runtime.
library;

enum FocusKind {
  unknown(0),
  easy(1),
  medium(2),
  hard(3);

  const FocusKind(this.discriminant);

  /// Stable integer matching the C ABI in the native runtime.
  final int discriminant;

  /// Decode an FFI-side discriminant. Unknown values fall back to
  /// [FocusKind.unknown].
  static FocusKind fromDiscriminant(int value) {
    return FocusKind.values.firstWhere(
      (k) => k.discriminant == value,
      orElse: () => FocusKind.unknown,
    );
  }
}
