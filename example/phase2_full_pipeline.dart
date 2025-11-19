import 'package:flutter/material.dart';
import 'package:hsi_flutter/hsi_flutter.dart';

/// Phase 2 Complete Pipeline Test
///
/// Demonstrates the full HSI pipeline with all modules:
/// - Capabilities & Consent
/// - Wear Module (biosignals)
/// - Phone Module (motion, screen state)
/// - Behavior Module (user interactions)
/// - HSI Runtime (fusion & heads)
void main() {
  runApp(const FullPipelineApp());
}

class FullPipelineApp extends StatelessWidget {
  const FullPipelineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HSI Phase 2 - Full Pipeline',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const FullPipelinePage(),
    );
  }
}

class FullPipelinePage extends StatefulWidget {
  const FullPipelinePage({super.key});

  @override
  State<FullPipelinePage> createState() => _FullPipelinePageState();
}

class _FullPipelinePageState extends State<FullPipelinePage> {
  final HSI _hsi = HSI.shared;
  bool _isConfigured = false;
  bool _isRunning = false;
  HumanStateVector? _currentState;
  Map<String, String>? _moduleStatuses;
  String _statusMessage = 'Not configured';
  int _updateCount = 0;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _configure() async {
    try {
      setState(() {
        _statusMessage = 'Configuring...';
      });

      await _hsi.configure(
        appKey: 'test_app_key',
        userId: 'test_user_123',
        config: SynheartConfig.defaults(),
      );

      // Grant all consents for testing
      await _hsi.updateConsent(ConsentSnapshot.all());

      setState(() {
        _isConfigured = true;
        _moduleStatuses = _hsi.getModuleStatuses();
        _statusMessage = 'Configured successfully';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HSI configured - all modules ready')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Configuration failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Configuration failed: $e')),
        );
      }
    }
  }

  Future<void> _start() async {
    try {
      setState(() {
        _statusMessage = 'Starting...';
      });

      await _hsi.start();

      // Subscribe to HSV updates
      _hsi.onStateUpdate.listen((hsv) {
        setState(() {
          _currentState = hsv;
          _updateCount++;
        });
      });

      setState(() {
        _isRunning = true;
        _moduleStatuses = _hsi.getModuleStatuses();
        _statusMessage = 'Running';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HSI pipeline started - receiving HSV updates')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Start failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Start failed: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    try {
      await _hsi.stop();

      setState(() {
        _isRunning = false;
        _moduleStatuses = _hsi.getModuleStatuses();
        _statusMessage = 'Stopped';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('HSI stopped')),
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
    _hsi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Record tap events for behavior module
        if (_isRunning) {
          _hsi.behaviorModule?.eventStream.recordTap(Offset.zero);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('HSI Phase 2 - Full Pipeline'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status
              _buildStatusCard(),
              const SizedBox(height: 16),

              // Controls
              if (!_isConfigured)
                ElevatedButton(
                  onPressed: _configure,
                  child: const Text('Configure HSI'),
                ),

              if (_isConfigured && !_isRunning)
                ElevatedButton(
                  onPressed: _start,
                  child: const Text('Start HSI Pipeline'),
                ),

              if (_isRunning)
                ElevatedButton(
                  onPressed: _stop,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Stop HSI'),
                ),

              const SizedBox(height: 16),

              // Module statuses
              if (_moduleStatuses != null) _buildModuleStatusesCard(),

              const SizedBox(height: 16),

              // Current state (HSV)
              if (_currentState != null) ...[
                _buildStateCard(),
              ] else if (_isRunning)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: Text('Waiting for first HSV update...')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
            _buildStatusRow('Configured', _isConfigured.toString()),
            _buildStatusRow('Running', _isRunning.toString()),
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
            }).toList(),
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
          _buildMetric('Typing Burstiness', _currentState!.behavior.typingBurstiness),
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
