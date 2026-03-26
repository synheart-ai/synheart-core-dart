/// SRM context strata for baseline partitioning.
///
/// Each stratum maintains an independent reference buffer to prevent
/// distributional contamination across contexts (SRM.pdf §3.2).
enum SRMStratum {
  sleep,
  rest,
  breathing,
  morning,
  other;

  static SRMStratum? fromString(String value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }
}
