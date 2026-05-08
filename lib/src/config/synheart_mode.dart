/// Operational modes for Synheart Core.
///
/// Modes control what data is persisted and what may be uploaded.
/// The runtime pipeline is mode-agnostic — modes only affect storage behavior.
///
/// See RFC-CORE-0003 for the full specification.
enum SynheartMode {
  /// Privacy-first consumer mode. Only HSI snapshots, session summaries,
  /// and baselines are persisted. No raw biosignals, no app metrics.
  personal,

  /// Behavioral insight mode. HSI + application metrics (reaction time,
  /// accuracy, etc.) are persisted. No raw biosignals.
  insight,

  /// Scientific research mode. Everything is persisted including raw
  /// biosignals. Requires explicit consent via [SynheartPrivacyConfig.allowResearch].
  research,
}
