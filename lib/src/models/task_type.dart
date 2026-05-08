/// Personalization task tags supplied by the host.
///
/// Mirrors `synheart_personalization_runtime::TaskType` and the
/// `synheart_core_set_task_type` discriminant table:
/// `0=unknown, 1=focus, 2=recovery, 3=movement, 4=conversation`.
///
/// Used by the engine's Stage 5 confidence modulation so e.g. mid-workout
/// `Movement` dampens cognitive head confidence per
/// the personalization spec.
library;

enum TaskType {
  unknown(0),
  focus(1),
  recovery(2),
  movement(3),
  conversation(4);

  const TaskType(this.discriminant);

  /// Stable integer matching the C ABI in the native runtime.
  final int discriminant;

  /// Decode an FFI-side discriminant. Unknown values fall back to
  /// [TaskType.unknown].
  static TaskType fromDiscriminant(int value) {
    return TaskType.values.firstWhere(
      (t) => t.discriminant == value,
      orElse: () => TaskType.unknown,
    );
  }
}
