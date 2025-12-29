import 'package:flutter/material.dart';
import 'package:synheart_core/synheart_core.dart';

/// Test app for new module architecture
void main() {
  runApp(const NewArchitectureTestApp());
}

class NewArchitectureTestApp extends StatelessWidget {
  const NewArchitectureTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synheart Modules Test',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const NewArchitectureTestPage(),
    );
  }
}

class NewArchitectureTestPage extends StatefulWidget {
  const NewArchitectureTestPage({super.key});

  @override
  State<NewArchitectureTestPage> createState() =>
      _NewArchitectureTestPageState();
}

class _NewArchitectureTestPageState extends State<NewArchitectureTestPage> {
  bool _isConfigured = false;
  bool _isRunning = false;
  ConsentSnapshot? _currentConsent;
  Map<String, String>? _moduleStatuses;
  String _statusMessage = 'Not configured';

  @override
  void initState() {
    super.initState();
  }

  Future<void> _configure() async {
    try {
      setState(() {
        _statusMessage = 'Initializing...';
      });

      await Synheart.initialize(
        appKey: 'test_app_key',
        userId: 'test_user_123',
        config: SynheartConfig.defaults(),
      );

      setState(() {
        _isConfigured = true;
        _isRunning = true; // initialize starts immediately
        _currentConsent = Synheart.shared.currentConsent;
        _moduleStatuses = Synheart.shared.getModuleStatuses();
        _statusMessage = 'Initialized';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synheart initialized successfully')),
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
    // Synheart starts during initialize; keep this button for UI continuity.
    setState(() {
      _isRunning = true;
      _moduleStatuses = Synheart.shared.getModuleStatuses();
      _statusMessage = 'Running';
    });
  }

  Future<void> _stop() async {
    try {
      setState(() {
        _statusMessage = 'Stopping...';
      });

      await Synheart.stop();

      setState(() {
        _isRunning = false;
        _moduleStatuses = Synheart.shared.getModuleStatuses();
        _statusMessage = 'Stopped';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Synheart stopped')),
        );
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Stop failed: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stop failed: $e')),
        );
      }
    }
  }

  Future<void> _updateConsent(ConsentType type, bool granted) async {
    try {
      if (_currentConsent == null) return;

      ConsentSnapshot updated;
      switch (type) {
        case ConsentType.biosignals:
          updated = _currentConsent!.copyWith(biosignals: granted, timestamp: DateTime.now());
          break;
        case ConsentType.behavior:
          updated = _currentConsent!.copyWith(behavior: granted, timestamp: DateTime.now());
          break;
        case ConsentType.motion:
          updated = _currentConsent!.copyWith(motion: granted, timestamp: DateTime.now());
          break;
        case ConsentType.cloudUpload:
          updated = _currentConsent!.copyWith(cloudUpload: granted, timestamp: DateTime.now());
          break;
        case ConsentType.syni:
          updated = _currentConsent!.copyWith(syni: granted, timestamp: DateTime.now());
          break;
      }

      await Synheart.updateConsent(updated);

      setState(() {
        _currentConsent = Synheart.shared.currentConsent;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Consent updated: ${type.name} = $granted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update consent: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    Synheart.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use automatic behavior capture if synheart_behavior is initialized
    final synheartBehavior = Synheart.shared.behaviorModule?.synheartBehavior;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('Synheart Modules Test'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('Status: $_statusMessage'),
                    Text('Configured: $_isConfigured'),
                    Text('Running: $_isRunning'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Control buttons
            if (!_isConfigured)
              ElevatedButton(
                onPressed: _configure,
                child: const Text('Initialize Synheart'),
              ),

            if (_isConfigured && !_isRunning)
              ElevatedButton(onPressed: _start, child: const Text('Mark Running')),

            if (_isRunning)
              ElevatedButton(
                onPressed: _stop,
                child: const Text('Stop Synheart'),
              ),

            const SizedBox(height: 16),

            // Module statuses
            if (_moduleStatuses != null) ...[
              Card(
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
              ),
              const SizedBox(height: 16),
            ],

            // Consent controls
            if (_currentConsent != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Consent Management',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _buildConsentSwitch(
                        'Biosignals',
                        ConsentType.biosignals,
                        _currentConsent!.biosignals,
                      ),
                      _buildConsentSwitch(
                        'Behavior',
                        ConsentType.behavior,
                        _currentConsent!.behavior,
                      ),
                      _buildConsentSwitch(
                        'Motion',
                        ConsentType.motion,
                        _currentConsent!.motion,
                      ),
                      _buildConsentSwitch(
                        'Cloud Upload',
                        ConsentType.cloudUpload,
                        _currentConsent!.cloudUpload,
                      ),
                      _buildConsentSwitch(
                        'Syni',
                        ConsentType.syni,
                        _currentConsent!.syni,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    // Wrap with synheart_behavior's gesture detector for automatic capture
    if (synheartBehavior != null && _isRunning) {
      return synheartBehavior.wrapWithGestureDetector(scaffold);
    }
    return scaffold;
  }

  Widget _buildConsentSwitch(String label, ConsentType type, bool value) {
    return SwitchListTile(
      title: Text(label),
      value: value,
      onChanged: (newValue) => _updateConsent(type, newValue),
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
