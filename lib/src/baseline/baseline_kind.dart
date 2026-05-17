/// Discriminator for what kind of baseline a snapshot carries.
///
/// Mirror of `BaselineKind` in `synheart-engine-types::baseline`. Wire
/// form is the stable lowercase dotted string used as the cloud +
/// on-device dispatch column (`session.hsi_axes`,
/// `session.srm_metrics`, `longitudinal.wear`).
///
/// Adding a future kind: register a new variant + wire string here AND
/// in the Rust enum at the same time. `fromWire` returns null for
/// unknown wires so older SDKs reading a snapshot produced by a newer
/// runtime degrade gracefully (log + skip rather than panic).
enum BaselineKind {
  sessionHsiAxes('session.hsi_axes'),
  sessionSrmMetrics('session.srm_metrics'),
  longitudinalWear('longitudinal.wear');

  final String wire;
  const BaselineKind(this.wire);

  /// Parse from the wire string. Returns null on an unknown kind —
  /// the intended pattern is "log + skip" not "throw".
  static BaselineKind? fromWire(String? s) {
    if (s == null) return null;
    for (final v in BaselineKind.values) {
      if (v.wire == s) return v;
    }
    return null;
  }

  /// True for kinds that are scoped to a single session
  /// (`session.*` prefix). The envelope's `sessionId` is required when
  /// this is true and forbidden when false.
  bool get isSessionScoped => wire.startsWith('session.');
}

/// Maturity status of a session-level SRM metric. Mirrors
/// `SrmMetricStatus` in engine-types. Distinct from
/// [WearableBaselineStatusWire] — session SRM doesn't decay within a
/// session, so no `STALE` variant.
enum SrmMetricStatus {
  empty('EMPTY'),
  warming('WARMING'),
  ready('READY');

  final String wire;
  const SrmMetricStatus(this.wire);

  static SrmMetricStatus? fromWire(String? s) {
    if (s == null) return null;
    for (final v in SrmMetricStatus.values) {
      if (v.wire == s) return v;
    }
    return null;
  }
}
