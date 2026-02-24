import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:synheart_core/synheart_core.dart';
import '../providers/synheart_provider.dart';

/// Runtime diagnostics screen — shows native runtime status, version,
/// frame count, quality, live HSI JSON, and synthetic signal injection.
class RuntimeScreen extends StatefulWidget {
  const RuntimeScreen({super.key});

  @override
  State<RuntimeScreen> createState() => _RuntimeScreenState();
}

class _RuntimeScreenState extends State<RuntimeScreen> {
  final List<String> _hsiLog = [];
  StreamSubscription<String>? _hsiSubscription;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _hsiSubscription = Synheart.onHSIUpdate.listen((hsi) {
      setState(() {
        _hsiLog.insert(0, hsi);
        if (_hsiLog.length > 50) _hsiLog.removeLast();
      });
    });
    // Refresh diagnostics every second
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _hsiSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Runtime Diagnostics'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Consumer<SynheartProvider>(
        builder: (context, provider, child) {
          final diag = provider.runtimeDiagnostics;
          final isAvailable = diag['isAvailable'] as bool;
          final version = diag['version'] as String?;
          final frameCount = diag['frameCount'] as int;
          final lastQuality = diag['lastQuality'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Runtime Status Card
                _buildStatusCard(context, isAvailable, version, frameCount),
                const SizedBox(height: 16),

                // Last Quality
                _buildQualityCard(context, lastQuality),
                const SizedBox(height: 16),

                // Synthetic Signal Injection
                _buildInjectionCard(context),
                const SizedBox(height: 16),

                // Live HSI JSON
                _buildHsiLogCard(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    bool isAvailable,
    String? version,
    int frameCount,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isAvailable ? Icons.check_circle : Icons.cancel,
                  color: isAvailable ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  'Runtime Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _infoRow('Connected', isAvailable ? 'Yes' : 'No'),
            _infoRow('Version', version ?? 'N/A'),
            _infoRow('Frame Count', '$frameCount'),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityCard(BuildContext context, String? lastQuality) {
    String formattedQuality = 'No quality data yet';
    if (lastQuality != null) {
      try {
        final parsed = jsonDecode(lastQuality);
        const encoder = JsonEncoder.withIndent('  ');
        formattedQuality = encoder.convert(parsed);
      } catch (_) {
        formattedQuality = lastQuality;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last Quality',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                formattedQuality,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInjectionCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Synthetic Signal Injection',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _pushSyntheticRR,
                  child: const Text('Push RR'),
                ),
                FilledButton.tonal(
                  onPressed: _pushSyntheticHR,
                  child: const Text('Push HR'),
                ),
                FilledButton.tonal(
                  onPressed: _pushSyntheticBehavior,
                  child: const Text('Push Behavior'),
                ),
                FilledButton(
                  onPressed: _manualTick,
                  child: const Text('Tick'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHsiLogCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Live HSI JSON (${_hsiLog.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_hsiLog.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _hsiLog.clear()),
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 300,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _hsiLog.isEmpty
                  ? const Center(
                      child: Text(
                        'Waiting for HSI frames...',
                        style: TextStyle(color: Colors.grey, fontFamily: 'monospace'),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _hsiLog.length,
                      separatorBuilder: (_, __) => Divider(
                        color: Colors.grey.shade700,
                        height: 1,
                      ),
                      itemBuilder: (context, index) {
                        String formatted;
                        try {
                          final parsed = jsonDecode(_hsiLog[index]);
                          const encoder = JsonEncoder.withIndent('  ');
                          formatted = encoder.convert(parsed);
                        } catch (_) {
                          formatted = _hsiLog[index];
                        }
                        return SelectableText(
                          formatted,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: Colors.greenAccent,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _pushSyntheticRR() {
    final diag = Synheart.runtimeDiagnostics();
    if (diag['isAvailable'] != true) {
      _showSnackBar('Runtime not available');
      return;
    }
    // Access bridge directly via the runtime module
    final bridge = Synheart.shared.runtimeModule?.bridge;
    if (bridge == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Push a series of normal RR intervals (~800ms, ~75 bpm)
    for (var i = 0; i < 10; i++) {
      bridge.pushRr(now + i * 800, 800.0 + (i % 3) * 10.0);
    }
    _showSnackBar('Pushed 10 synthetic RR intervals');
  }

  void _pushSyntheticHR() {
    final bridge = Synheart.shared.runtimeModule?.bridge;
    if (bridge == null) {
      _showSnackBar('Runtime not available');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    bridge.pushHr(now, 72.0);
    _showSnackBar('Pushed HR: 72 bpm');
  }

  void _pushSyntheticBehavior() {
    final bridge = Synheart.shared.runtimeModule?.bridge;
    if (bridge == null) {
      _showSnackBar('Runtime not available');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    bridge.pushBehavior(now, 2, 1.0); // Touch event
    _showSnackBar('Pushed behavior event (touch)');
  }

  void _manualTick() {
    final bridge = Synheart.shared.runtimeModule?.bridge;
    if (bridge == null) {
      _showSnackBar('Runtime not available');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final hsi = bridge.tick(now);
    if (hsi != null) {
      setState(() {
        _hsiLog.insert(0, hsi);
        if (_hsiLog.length > 50) _hsiLog.removeLast();
      });
      _showSnackBar('Tick produced HSI frame');
    } else {
      _showSnackBar('Tick returned null (not enough data yet)');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
      );
    }
  }
}
