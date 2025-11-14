import 'package:flutter/material.dart';
import 'package:hsi_flutter/hsi_flutter.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HSI Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HSIExamplePage(),
    );
  }
}

class HSIExamplePage extends StatefulWidget {
  const HSIExamplePage({super.key});

  @override
  State<HSIExamplePage> createState() => _HSIExamplePageState();
}

class _HSIExamplePageState extends State<HSIExamplePage> {
  final HSI _hsi = HSI.shared;
  HumanStateVector? _currentState;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _initializeHSI();
  }

  Future<void> _initializeHSI() async {
    try {
      // Configure HSI with app key
      await _hsi.configure(appKey: 'YOUR_APP_KEY_HERE');

      // Listen to HSV updates
      _hsi.onStateUpdate.listen((hsv) {
        setState(() {
          _currentState = hsv;
        });
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing HSI: $e')),
        );
      }
    }
  }

  Future<void> _startHSI() async {
    try {
      await _hsi.start();
      setState(() {
        _isRunning = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting HSI: $e')),
        );
      }
    }
  }

  Future<void> _stopHSI() async {
    await _hsi.stop();
    setState(() {
      _isRunning = false;
    });
  }

  @override
  void dispose() {
    _hsi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HSI Flutter Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _isRunning ? _stopHSI : _startHSI,
              child: Text(_isRunning ? 'Stop HSI' : 'Start HSI'),
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
                _buildMetric('Cognitive Load', _currentState!.focus.cognitiveLoad),
                _buildMetric('Clarity', _currentState!.focus.clarity),
                _buildMetric('Distraction', _currentState!.focus.distraction),
              ]),
              const SizedBox(height: 16),
              _buildSection('Behavior', [
                _buildMetric('Typing Cadence', _currentState!.behavior.typingCadence),
                _buildMetric('Typing Burstiness', _currentState!.behavior.typingBurstiness),
                _buildMetric('Scroll Velocity', _currentState!.behavior.scrollVelocity),
                _buildMetric('Idle Gaps', _currentState!.behavior.idleGaps),
                _buildMetric('App Switch Rate', _currentState!.behavior.appSwitchRate),
              ]),
            ] else
              const Center(
                child: Text('No state data yet. Start HSI to begin receiving updates.'),
              ),
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

