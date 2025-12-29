import 'dart:async';
import 'package:flutter/material.dart';
import 'package:synheart_core/synheart_core.dart';

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
  StreamSubscription<HumanStateVector>? _subscription;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initializeSynheart() async {
    try {
      if (_isInitialized) return;

      // Initialize Core SDK
      await Synheart.initialize(
        appKey: 'YOUR_APP_KEY_HERE',
        userId: 'example_user_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Enable optional interpretation modules (so Emotion/Focus fields update)
      await Synheart.enableEmotion();
      await Synheart.enableFocus();

      _subscription = Synheart.onHSVUpdate.listen((hsv) {
        setState(() {
          _currentState = hsv;
        });
      });

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing Synheart: $e')),
        );
      }
    }
  }

  Future<void> _stopSynheart() async {
    await Synheart.stop();
    setState(() {
      _currentState = null;
      _isInitialized = false;
    });
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
              onPressed: isRunning ? _stopSynheart : _initializeSynheart,
              child: Text(isRunning ? 'Stop Synheart' : 'Initialize Synheart'),
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
                    'Cognitive Load', _currentState!.focus.cognitiveLoad),
                _buildMetric('Clarity', _currentState!.focus.clarity),
                _buildMetric('Distraction', _currentState!.focus.distraction),
              ]),
              const SizedBox(height: 16),
              _buildSection('Behavior', [
                _buildMetric(
                    'Typing Cadence', _currentState!.behavior.typingCadence),
                _buildMetric('Typing Burstiness',
                    _currentState!.behavior.typingBurstiness),
                _buildMetric(
                    'Scroll Velocity', _currentState!.behavior.scrollVelocity),
                _buildMetric('Idle Gaps', _currentState!.behavior.idleGaps),
                _buildMetric(
                    'App Switch Rate', _currentState!.behavior.appSwitchRate),
              ]),
            ] else
              const Center(
                child: Text(
                  'No state data yet. Initialize Synheart to begin receiving updates.',
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
