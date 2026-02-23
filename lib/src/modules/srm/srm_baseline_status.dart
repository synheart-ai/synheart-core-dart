/// SRM baseline status per stratum (SRM.pdf §6).
///
/// - [empty]: fewer than M_min accepted windows.
/// - [warming]: between M_min and M_ready accepted windows.
/// - [ready]: at least M_ready windows spanning at least D_min distinct days.
enum SRMBaselineStatus {
  empty,
  warming,
  ready;

  String toUpperCase() => name.toUpperCase();
}
