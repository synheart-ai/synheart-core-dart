import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:synheart_core/synheart_core.dart';
import 'package:synheart_behavior/synheart_behavior.dart' as sb;
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const SynheartExamplePage(),
    );
  }
}

class SynheartExamplePage extends StatefulWidget {
  const SynheartExamplePage({super.key});

  @override
  State<SynheartExamplePage> createState() => _SynheartExamplePageState();
}

class _SynheartExamplePageState extends State<SynheartExamplePage> {
  HumanStateVector? _currentState;
  bool _isInitialized = false;
  bool _isInitializing = false;
  StreamSubscription<HumanStateVector>? _subscription;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initializeSynheart() async {
    try {
      if (_isInitialized || _isInitializing) return;

      setState(() {
        _isInitializing = true;
      });

      // Request Android phone state permission BEFORE initializing Synheart
      // This prevents the CallCollector error during initialization
      if (mounted) {
        final phoneStatus = await Permission.phone.status;
        if (!phoneStatus.isGranted) {
          print(
            '[Synheart Example] Requesting phone permission before initialization...',
          );
          final result = await Permission.phone.request();
          if (result.isGranted) {
            print('[Synheart Example] Phone permission granted');
          } else {
            print('[Synheart Example] Phone permission denied: $result');
          }
        }
      }

      // Initialize Core SDK
      await Synheart.initialize(
        appKey: 'YOUR_APP_KEY_HERE',
        userId: 'example_user_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Grant consent for data collection (required for HSV updates)
      print('[Synheart Example] Granting consent for data collection...');
      await Synheart.grantConsent('biosignals');
      await Synheart.grantConsent('behavior');
      await Synheart.grantConsent('phoneContext');
      print('[Synheart Example] Consent granted');

      // Enable optional interpretation modules (so Emotion/Focus fields update)
      await Synheart.enableEmotion();
      await Synheart.enableFocus();

      // Request permissions for behavior SDK (notification and call permissions)
      // Wait a bit for the behavior module to fully initialize
      await Future.delayed(const Duration(milliseconds: 500));

      // Try to get synheartBehavior, with retries if it's not ready yet
      sb.SynheartBehavior? synheartBehavior;
      for (int i = 0; i < 5; i++) {
        synheartBehavior = Synheart.shared.behaviorModule?.synheartBehavior;
        if (synheartBehavior != null) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (synheartBehavior != null) {
        print('[Synheart Example] Requesting permissions...');
        // Request notification permission
        await _checkAndRequestNotificationPermission(synheartBehavior);
        // Request call permission (fixes READ_PHONE_STATE error)
        await _checkAndRequestCallPermission(synheartBehavior);
        print('[Synheart Example] Permission requests completed');
      } else {
        print(
          '[Synheart Example] Warning: synheartBehavior is null after retries, cannot request permissions',
        );
      }

      _subscription = Synheart.onHSVUpdate.listen((hsv) {
        print(
          '[Synheart Example] Received HSV update: timestamp=${hsv.timestamp}',
        );

        // Log HSI data as JSON
        try {
          // Use JsonEncoder with indent for pretty printing
          const encoder = JsonEncoder.withIndent('  ');

          final json = encoder.convert(hsv.toJson());
          print(
            '[Synheart Example] HSI Data (JSON) - Length: ${json.length} chars',
          );
          _printLongString('[Synheart Example] HSI Data (JSON):', json);

          // Also log HSI 1.0 format (canonical export format)
          final hsi10 = hsv.toHSI10();
          final hsi10Json = encoder.convert(hsi10.toJson());
          print(
            '[Synheart Example] HSI 1.0 Export (JSON) - Length: ${hsi10Json.length} chars',
          );
          _printLongString(
            '[Synheart Example] HSI 1.0 Export (JSON):',
            hsi10Json,
          );
        } catch (e) {
          print('[Synheart Example] Error encoding HSI to JSON: $e');
        }

        setState(() {
          _currentState = hsv;
        });
      });

      // Log initial state
      print('[Synheart Example] Synheart initialized successfully');
      print(
        '[Synheart Example] Waiting for HSV updates (may take up to 30 seconds for first update)...',
      );

      setState(() {
        _isInitialized = true;
        _isInitializing = false;
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing Synheart: $e')),
        );
      }
    }
  }

  Future<void> _checkAndRequestNotificationPermission(
    sb.SynheartBehavior? behavior,
  ) async {
    if (behavior == null) return;

    try {
      final hasPermission = await behavior.checkNotificationPermission();
      if (!hasPermission) {
        if (mounted) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Notification Permission'),
              content: const Text(
                'To track notification events, please enable notification access.\n\n'
                'On Android: You will be taken to system settings to enable notification access.\n'
                'On iOS: A permission dialog will appear.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );

          if (shouldRequest == true) {
            await behavior.requestNotificationPermission();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please enable notification access in settings if prompted.',
                  ),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      // Silently fail - permission request is optional
      print('Failed to check notification permission: $e');
    }
  }

  Future<void> _checkAndRequestCallPermission(
    sb.SynheartBehavior? behavior,
  ) async {
    if (behavior == null) return;

    try {
      print('[Synheart Example] Checking call permission...');
      final hasPermission = await behavior.checkCallPermission();
      print('[Synheart Example] Call permission status: $hasPermission');
      if (!hasPermission) {
        if (mounted) {
          final shouldRequest = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Call Permission'),
              content: const Text(
                'To track call events, please enable phone state access.\n\n'
                'On Android: A permission dialog will appear.\n'
                'On iOS: Call monitoring works automatically.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );

          if (shouldRequest == true) {
            await behavior.requestCallPermission();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please grant phone state permission if prompted.',
                  ),
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      // Silently fail - permission request is optional
      print('Failed to check call permission: $e');
    }
  }

  Future<void> _stopSynheart() async {
    try {
      await Synheart.stop();
      setState(() {
        _currentState = null;
        _isInitialized = false;
        _isInitializing = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error stopping Synheart: $e')));
      }
    }
  }

  /// Print a long string in chunks to avoid Flutter's print() truncation
  void _printLongString(String prefix, String content) {
    const maxChunkLength = 800; // Flutter print() limit is around 1024 chars
    print(prefix);

    if (content.length <= maxChunkLength) {
      print(content);
      return;
    }

    // Split into chunks
    for (int i = 0; i < content.length; i += maxChunkLength) {
      final end = (i + maxChunkLength < content.length)
          ? i + maxChunkLength
          : content.length;
      print(content.substring(i, end));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    Synheart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use automatic behavior capture if synheart_behavior is initialized
    final synheartBehavior = Synheart.shared.behaviorModule?.synheartBehavior;
    final isRunning = _isInitialized;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Synheart Flutter Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isInitializing
                  ? null
                  : (isRunning ? _stopSynheart : _initializeSynheart),
              child: _isInitializing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Initializing...'),
                      ],
                    )
                  : Text(isRunning ? 'Stop Synheart' : 'Initialize Synheart'),
            ),
            const SizedBox(height: 24),
            if (_currentState != null) ...[
              _buildSection('Emotion', [
                _buildMetric('Stress', _currentState!.emotion.stress),
                _buildMetric('Calm', _currentState!.emotion.calm),
                _buildMetric('Engagement', _currentState!.emotion.engagement),
                _buildMetric('Activation', _currentState!.emotion.activation),
                _buildMetric('Valence', _currentState!.emotion.valence),
              ]),
              const SizedBox(height: 16),
              _buildSection('Focus', [
                _buildMetric('Score', _currentState!.focus.score),
                _buildMetric(
                  'Cognitive Load',
                  _currentState!.focus.cognitiveLoad,
                ),
                _buildMetric('Clarity', _currentState!.focus.clarity),
                _buildMetric('Distraction', _currentState!.focus.distraction),
              ]),
              const SizedBox(height: 16),
              _buildSection('Behavior', [
                _buildMetric(
                  'Typing Cadence',
                  _currentState!.behavior.typingCadence,
                ),
                _buildMetric(
                  'Typing Burstiness',
                  _currentState!.behavior.typingBurstiness,
                ),
                _buildMetric(
                  'Scroll Velocity',
                  _currentState!.behavior.scrollVelocity,
                ),
                _buildMetric('Idle Gaps', _currentState!.behavior.idleGaps),
                _buildMetric(
                  'App Switch Rate',
                  _currentState!.behavior.appSwitchRate,
                ),
              ]),
            ] else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!_isInitialized)
                      const Text(
                        'No state data yet. Initialize Synheart to begin receiving updates.',
                      )
                    else ...[
                      const Text(
                        'Waiting for data...',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'HSV updates appear every 30 seconds when data is collected.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Interact with the app (scroll, type, etc.) to generate behavior data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    // Wrap with synheart_behavior's gesture detector for automatic capture
    if (synheartBehavior != null && isRunning) {
      return synheartBehavior.wrapWithGestureDetector(scaffold);
    }
    return scaffold;
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
            value.toStringAsFixed(2),
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
