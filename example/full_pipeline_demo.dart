import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_core/synheart_core.dart';

/// Full pipeline demo
///
/// Demonstrates the Synheart pipeline end-to-end:
/// - Capabilities & Consent
/// - Wear Module (biosignals)
/// - Phone Module (motion, screen state)
/// - Behavior Module (user interactions)
/// - HSI Runtime (fusion engine producing HSV)
void main() {
  runApp(const FullPipelineDemoApp());
}

class FullPipelineDemoApp extends StatelessWidget {
  const FullPipelineDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart - Full Pipeline Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FullPipelineDemoPage(),
    );
  }
}

class FullPipelineDemoPage extends StatefulWidget {
  const FullPipelineDemoPage({super.key});

  @override
  State<FullPipelineDemoPage> createState() => _FullPipelineDemoPageState();
}

class _FullPipelineDemoPageState extends State<FullPipelineDemoPage> {
  bool _isInitialized = false;
  bool _isSubscribed = false;
  HumanStateVector? _currentState;
  Map<String, String>? _moduleStatuses;
  String _statusMessage = 'Not initialized';
  int _updateCount = 0;
  StreamSubscription<HumanStateVector>? _subscription;

  Future<void> _initialize() async {
    try {
      setState(() {
        _statusMessage = 'Initializing...';
      });

      await Synheart.initialize(
        appKey: 'test_app_key',
        userId: 'test_user_123',
        config: SynheartConfig.defaults(),
      );

      // Grant all consents for demo/testing
      await Synheart.updateConsent(ConsentSnapshot.all());

      setState(() {
        _isInitialized = true;
        _moduleStatuses = Synheart.shared.getModuleStatuses();
        _statusMessage = 'Initialized';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synheart initialized - all modules ready')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Initialization failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Initialization failed: $e')),
        );
      }
    }
  }

  Future<void> _subscribe() async {
    try {
      _subscription ??= Synheart.onHSVUpdate.listen((hsv) {
        setState(() {
          _currentState = hsv;
          _updateCount++;
        });
      });

      setState(() {
        _isSubscribed = true;
        _moduleStatuses = Synheart.shared.getModuleStatuses();
        _statusMessage = 'Subscribed to HSV';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Subscribed - receiving HSV updates')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Subscribe failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Subscribe failed: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    try {
      await Synheart.stop();

      await _subscription?.cancel();
      _subscription = null;

      setState(() {
        _isSubscribed = false;
        _isInitialized = false;
        _moduleStatuses = Synheart.shared.getModuleStatuses();
        _statusMessage = 'Stopped';
        _currentState = null;
        _updateCount = 0;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synheart stopped')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop failed: $e')),
        );
      }
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
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Synheart - Full Pipeline Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            const SizedBox(height: 16),

            if (!_isInitialized)
              ElevatedButton(
                onPressed: _initialize,
                child: const Text('Initialize'),
              ),

            if (_isInitialized && !_isSubscribed)
              ElevatedButton(
                onPressed: _subscribe,
                child: const Text('Subscribe to HSV'),
              ),

            if (_isInitialized)
              ElevatedButton(
                onPressed: _stop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Stop'),
              ),

            const SizedBox(height: 16),

            if (_moduleStatuses != null) _buildModuleStatusesCard(),

            const SizedBox(height: 16),

            if (_currentState != null) ...[
              _buildStateCard(),
            ] else if (_isSubscribed)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: Text('Waiting for first HSV update...')),
                ),
              ),
          ],
        ),
      ),
    );

    // Wrap with synheart_behavior's gesture detector for automatic capture
    // Falls back to manual instrumentation if not available
    if (synheartBehavior != null && _isSubscribed) {
      return synheartBehavior.wrapWithGestureDetector(scaffold);
    } else if (_isSubscribed) {
      return GestureDetector(
        onTap: () {
          Synheart.shared.behaviorModule?.eventStream.recordTap(Offset.zero);
        },
        child: scaffold,
      );
    }

    return scaffold;
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pipeline Status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _buildStatusRow('Status', _statusMessage),
            _buildStatusRow('Initialized', _isInitialized.toString()),
            _buildStatusRow('Subscribed', _isSubscribed.toString()),
            _buildStatusRow('HSV Updates', _updateCount.toString()),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleStatusesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Module Statuses',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ..._moduleStatuses!.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key),
                    Chip(
                      label: Text(entry.value),
                      backgroundColor: _getStatusColor(entry.value),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildStateCard() {
    return Column(
      children: [
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
          _buildMetric('Cognitive Load', _currentState!.focus.cognitiveLoad),
          _buildMetric('Clarity', _currentState!.focus.clarity),
          _buildMetric('Distraction', _currentState!.focus.distraction),
        ]),
        const SizedBox(height: 16),
        _buildSection('Behavior', [
          _buildMetric('Typing Cadence', _currentState!.behavior.typingCadence),
          _buildMetric(
            'Typing Burstiness',
            _currentState!.behavior.typingBurstiness,
          ),
          _buildMetric('Scroll Velocity', _currentState!.behavior.scrollVelocity),
          _buildMetric('Idle Gaps', _currentState!.behavior.idleGaps),
          _buildMetric('App Switch Rate', _currentState!.behavior.appSwitchRate),
        ]),
      ],
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
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
          Row(
            children: [
              Text(
                value.toStringAsFixed(2),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: LinearProgressIndicator(
                  value: value.clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[300],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'running':
        return Colors.green.shade200;
      case 'initialized':
      case 'stopped':
        return Colors.blue.shade200;
      case 'error':
        return Colors.red.shade200;
      default:
        return Colors.grey.shade200;
    }
  }
}


