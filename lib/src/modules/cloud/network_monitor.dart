import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectivityController =
      StreamController<bool>.broadcast();

  StreamSubscription? _subscription;
  bool _isOnline = false;

  NetworkMonitor() {
    _init();
  }

  void _init() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(result);

    // Listen for changes
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = _isConnected(result);

      // Emit event only on transitions
      if (wasOnline != _isOnline) {
        _connectivityController.add(_isOnline);
      }
    });
  }

  bool _isConnected(List<ConnectivityResult> results) {
    // Consider online if any connection type is available
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.ethernet,
    );
  }

  bool get isOnline => _isOnline;

  Stream<bool> get connectivityStream => _connectivityController.stream;

  void dispose() {
    _subscription?.cancel();
    _connectivityController.close();
  }
}
