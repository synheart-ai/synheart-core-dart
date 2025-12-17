import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hsi_flutter/hsi_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phone Module Data',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const PhoneModulePage(),
    );
  }
}

class PhoneModulePage extends StatefulWidget {
  const PhoneModulePage({super.key});

  @override
  State<PhoneModulePage> createState() => _PhoneModulePageState();
}

class _PhoneModulePageState extends State<PhoneModulePage>
    with WidgetsBindingObserver {
  final HSI _hsi = HSI.shared;
  PhoneWindowFeatures? _phoneFeatures;
  Timer? _updateTimer;
  bool _isInitialized = false;
  String _statusMessage = 'Initializing...';
  bool _hasUsageStatsPermission = false;
  bool _hasNotificationPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _initializePhoneModule();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    _hsi.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Check permissions when app resumes (user might have granted permission)
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    try {
      const platform = MethodChannel(
        'com.synheart.hsi_flutter_example/settings',
      );
      final usageStats =
          await platform.invokeMethod<bool>('checkUsageStatsPermission') ??
          false;
      final notification =
          await platform.invokeMethod<bool>('checkNotificationPermission') ??
          false;

      final bool usageStatsChanged = _hasUsageStatsPermission != usageStats;
      final bool notificationChanged =
          _hasNotificationPermission != notification;

      setState(() {
        _hasUsageStatsPermission = usageStats;
        _hasNotificationPermission = notification;
      });

      // If permissions were just granted, the streams should automatically recover
      // since they use cancelOnError: false and the native plugins keep checking permissions
      if (_isInitialized && (usageStatsChanged || notificationChanged)) {
        if (usageStatsChanged && usageStats) {
          print(
            '[Example] Usage Stats permission granted - app tracking should automatically resume',
          );
          // No need to restart - the app tracker stream will automatically recover
          // The native plugin keeps checking for permission and will start sending events
        }
        if (notificationChanged && notification) {
          print(
            '[Example] Notification permission granted - notification tracking should automatically resume',
          );
          // No need to restart - the notification tracker stream will automatically recover
          // The native plugin keeps checking for permission and will start sending events
        }
      }
    } catch (e) {
      print('Error checking permissions: $e');
    }
  }

  Future<void> _initializePhoneModule() async {
    try {
      setState(() {
        _statusMessage = 'Configuring HSI...';
      });

      // Configure Core SDK
      await _hsi.configure(
        appKey: 'YOUR_APP_KEY_HERE',
        userId: 'example_user_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Grant motion consent (required for phone module)
      await _hsi.updateConsent(
        ConsentSnapshot(
          biosignals: false,
          behavior: false,
          motion: true, // Required for phone module
          cloudUpload: false,
          syni: false,
          timestamp: DateTime.now(),
        ),
      );

      // Start HSI to activate phone module
      // Note: Wear module may fail (e.g., no permissions), but phone module should still work
      try {
        await _hsi.start();
      } catch (e) {
        // Log the error but continue - phone module may still work
        print('[Example] HSI start warning: $e');
        // Check if phone module is available
        if (_hsi.phoneModule == null) {
          throw Exception('Phone module not available');
        }
      }

      setState(() {
        _isInitialized = true;
        _statusMessage = 'Phone module active - collecting data...';
      });

      // Wait a bit for data to start collecting, then start polling
      await Future.delayed(const Duration(seconds: 2));
      _checkPermissions(); // Check permissions after initialization
      _startPolling();
    } catch (e, stackTrace) {
      print('[Example] Initialization error: $e');
      print(stackTrace);
      setState(() {
        _isInitialized = false;
        _statusMessage = 'Error initializing: ${e.toString()}';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _startPolling() {
    // Poll every 500ms to show real-time updates
    _updateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final phoneModule = _hsi.phoneModule;
      if (phoneModule != null) {
        // Get features for 30-second window (primary window)
        final features = phoneModule.features(WindowType.window30s);
        setState(() {
          _phoneFeatures = features;
        });
      }
    });
  }

  String _getActivityName(ActivityCode code) {
    switch (code) {
      case ActivityCode.stationary:
        return 'Stationary';
      case ActivityCode.walking:
        return 'Walking';
      case ActivityCode.running:
        return 'Running';
      case ActivityCode.inVehicle:
        return 'In Vehicle';
      case ActivityCode.unknown:
        return 'Unknown';
    }
  }

  /// Open Android settings for Usage Stats permission
  Future<void> _openUsageStatsSettings() async {
    try {
      const platform = MethodChannel(
        'com.synheart.hsi_flutter_example/settings',
      );
      await platform.invokeMethod('openUsageStatsSettings');
    } catch (e) {
      // Fallback: Show instructions
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'To track app switching, please grant Usage Stats permission:\n\n'
              '1. Go to Settings\n'
              '2. Find "Apps" or "Special app access"\n'
              '3. Select "Usage access"\n'
              '4. Find this app and enable it',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// Open Android settings for Notification access permission
  Future<void> _openNotificationSettings() async {
    try {
      const platform = MethodChannel(
        'com.synheart.hsi_flutter_example/settings',
      );
      await platform.invokeMethod('openNotificationSettings');
    } catch (e) {
      // Fallback: Show instructions
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Permission Required'),
            content: const Text(
              'To track notifications, please grant Notification access:\n\n'
              '1. Go to Settings\n'
              '2. Find "Apps" or "Special app access"\n'
              '3. Select "Notification access"\n'
              '4. Find this app and enable it',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Module Data'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isInitialized
          ? RefreshIndicator(
              onRefresh: () async {
                final phoneModule = _hsi.phoneModule;
                if (phoneModule != null) {
                  final features = phoneModule.features(WindowType.window30s);
                  setState(() {
                    _phoneFeatures = features;
                  });
                }
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: _phoneFeatures != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSection('Motion Data', [
                            _buildMetric(
                              'Motion Level',
                              _phoneFeatures!.motionLevel,
                            ),
                            _buildMetric(
                              'Motion Vector X',
                              _phoneFeatures!.motionVector[0],
                            ),
                            _buildMetric(
                              'Motion Vector Y',
                              _phoneFeatures!.motionVector[1],
                            ),
                            _buildMetric(
                              'Motion Vector Z',
                              _phoneFeatures!.motionVector[2],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Gyroscope (Rotation)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildMetric(
                              'Gyroscope X',
                              _phoneFeatures!.gyroscopeVector[0],
                            ),
                            _buildMetric(
                              'Gyroscope Y',
                              _phoneFeatures!.gyroscopeVector[1],
                            ),
                            _buildMetric(
                              'Gyroscope Z',
                              _phoneFeatures!.gyroscopeVector[2],
                            ),
                            _buildTextMetric(
                              'Activity',
                              _getActivityName(_phoneFeatures!.activityCode),
                            ),
                            _buildMetric(
                              'Idle Ratio',
                              _phoneFeatures!.idleRatio,
                            ),
                          ]),
                          const SizedBox(height: 16),
                          _buildSection('Screen & Context', [
                            _buildMetric(
                              'Screen On Ratio',
                              _phoneFeatures!.screenOnRatio,
                            ),
                            if (_phoneFeatures!.screenOnRatio == 0.0)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '💡 Tip: Keep the screen on to see this value increase',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.orange),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('App Switch Rate'),
                                  Text(
                                    '${_phoneFeatures!.appSwitchRate.toStringAsFixed(2)} /min',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_phoneFeatures!.appSwitchRate == 0.0 &&
                                !_hasUsageStatsPermission)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  children: [
                                    Text(
                                      '💡 Tip: Switch between apps to see this value increase',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.orange),
                                    ),
                                    const SizedBox(height: 4),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _openUsageStatsSettings();
                                        // Check permission after returning from settings
                                        // Wait a bit longer to ensure Android has updated permission state
                                        await Future.delayed(
                                          const Duration(milliseconds: 1000),
                                        );
                                        _checkPermissions();
                                        // Check again after a short delay to catch delayed updates
                                        await Future.delayed(
                                          const Duration(milliseconds: 500),
                                        );
                                        _checkPermissions();
                                      },
                                      icon: const Icon(
                                        Icons.settings,
                                        size: 16,
                                      ),
                                      label: const Text('Grant Permission'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_phoneFeatures!.appSwitchRate == 0.0 &&
                                _hasUsageStatsPermission)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '✅ Permission granted. Switch between apps to see data.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.green),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Notification Rate'),
                                  Text(
                                    '${_phoneFeatures!.notificationRate.toStringAsFixed(2)} /min',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_phoneFeatures!.notificationRate == 0.0 &&
                                !_hasNotificationPermission)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Column(
                                  children: [
                                    Text(
                                      '💡 Tip: Grant notification access to track notifications',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: Colors.orange),
                                    ),
                                    const SizedBox(height: 4),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await _openNotificationSettings();
                                        // Check permission after returning from settings
                                        await Future.delayed(
                                          const Duration(milliseconds: 500),
                                        );
                                        _checkPermissions();
                                      },
                                      icon: const Icon(
                                        Icons.settings,
                                        size: 16,
                                      ),
                                      label: const Text('Grant Permission'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (_phoneFeatures!.notificationRate == 0.0 &&
                                _hasNotificationPermission)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(
                                  '✅ Permission granted. Receive notifications to see data.',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.green),
                                ),
                              ),
                          ]),
                          if (_phoneFeatures!.appContext != null) ...[
                            const SizedBox(height: 16),
                            _buildSection('App Context (Extended)', [
                              _buildTextMetric(
                                'Current App',
                                _phoneFeatures!.appContext!['currentApp']
                                        ?.toString() ??
                                    'N/A',
                              ),
                              _buildTextMetric(
                                'Total Switches',
                                _phoneFeatures!.appContext!['totalSwitches']
                                        ?.toString() ??
                                    '0',
                              ),
                            ]),
                          ],
                          if (_phoneFeatures!.rawNotifications != null &&
                              _phoneFeatures!.rawNotifications!.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildSection('Raw Notifications (Research)', [
                              _buildTextMetric(
                                'Count',
                                _phoneFeatures!.rawNotifications!.length
                                    .toString(),
                              ),
                            ]),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Last updated: ${DateTime.now().toString().substring(11, 19)}',
                            style: Theme.of(context).textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(_statusMessage),
                            const SizedBox(height: 8),
                            const Text(
                              'Waiting for data...\nMake sure motion consent is granted.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toStringAsFixed(3),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextMetric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
