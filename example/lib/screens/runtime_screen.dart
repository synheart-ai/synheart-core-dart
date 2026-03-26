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

  /// Lab session state (per #Guidelines/flutter_guide.md Lab Sessions)
  bool _labActive = false;
  final List<String> _openWindowIds = [];
  String? _labResultJson;
  String _labOpenWindowType = 'phase';
  final TextEditingController _labOpenLabelController = TextEditingController(text: 'baseline_rest');
  final TextEditingController _labSetValuesController = TextEditingController(text: '{"score": 0}');
  String? _labSelectedWindowId;
  String? _labSetValuesWindowId;

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
    _labOpenLabelController.dispose();
    _labSetValuesController.dispose();
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

                // Lab Session (protocol / phase / trial windows)
                _buildLabCard(context),
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

  Widget _buildLabCard(BuildContext context) {
    final isLabAvailable = Synheart.isLabAvailable;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isLabAvailable ? Icons.science : Icons.science_outlined,
                  color: isLabAvailable ? Colors.purple : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Lab Session',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                if (_labActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('Active', style: TextStyle(fontSize: 12, color: Colors.purple.shade800)),
                  ),
              ],
            ),
            if (!isLabAvailable) ...[
              const SizedBox(height: 8),
              Text(
                'Lab C API not available (native runtime may be built without lab feature).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!_labActive)
                    FilledButton(
                      onPressed: _labStart,
                      child: const Text('Start lab'),
                    )
                  else ...[
                    FilledButton.tonal(
                      onPressed: _labFinalize,
                      child: const Text('Finalize lab'),
                    ),
                  ],
                ],
              ),
              if (_labActive) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Text('Open window', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: DropdownButtonFormField<String>(
                        value: _labOpenWindowType,
                        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                        items: const [
                          DropdownMenuItem(value: 'protocol', child: Text('protocol')),
                          DropdownMenuItem(value: 'phase', child: Text('phase')),
                          DropdownMenuItem(value: 'level', child: Text('level')),
                          DropdownMenuItem(value: 'trial', child: Text('trial')),
                        ],
                        onChanged: (v) => setState(() => _labOpenWindowType = v ?? 'phase'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _labOpenLabelController,
                        decoration: const InputDecoration(labelText: 'Label', isDense: true),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _labOpenWindow,
                      child: const Text('Open'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Open windows: ${_openWindowIds.length}', style: Theme.of(context).textTheme.bodySmall),
                if (_openWindowIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _labSelectedWindowId ?? _openWindowIds.first,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                          items: _openWindowIds.map((id) => DropdownMenuItem(value: id, child: Text(id.length > 20 ? '${id.substring(0, 20)}…' : id))).toList(),
                          onChanged: (v) => setState(() => _labSelectedWindowId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _labCloseWindow,
                        child: const Text('Close window'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          value: _labSetValuesWindowId ?? _openWindowIds.first,
                          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                          items: _openWindowIds.map((id) => DropdownMenuItem(value: id, child: Text(id.length > 20 ? '${id.substring(0, 20)}…' : id))).toList(),
                          onChanged: (v) => setState(() => _labSetValuesWindowId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _labSetValuesController,
                          decoration: const InputDecoration(labelText: 'Values JSON', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: _labSetWindowValues,
                        child: const Text('Set values'),
                      ),
                    ],
                  ),
                ],
              ],
              if (_labResultJson != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Last finalize result', style: Theme.of(context).textTheme.labelLarge),
                    TextButton(
                      onPressed: () => setState(() => _labResultJson = null),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 200),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _formatLabResultJson(_labResultJson!),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatLabResultJson(String raw) {
    try {
      final parsed = jsonDecode(raw);
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(parsed);
    } catch (_) {
      return raw;
    }
  }

  void _labStart() {
    if (!Synheart.isLabAvailable) {
      _showSnackBar('Lab not available');
      return;
    }
    final provider = context.read<SynheartProvider>();
    final userId = provider.userId ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    final protocolJson = jsonEncode({
      'namespace': 'synheart.pulse_focus',
      'protocol_version': '1.0',
      'protocol_id': 'pf_trial_01',
      'parameters': {'difficulty': 'medium'},
      'app_id': 'ai.synheart.example',
      'device_id': 'device_${userId}',
      'user_id': userId,
    });
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final err = Synheart.labStart(protocolJson, nowMs);
    if (err != null) {
      _showSnackBar('Lab start failed: $err');
      return;
    }
    setState(() {
      _labActive = true;
      _openWindowIds.clear();
      _labResultJson = null;
      _labSelectedWindowId = null;
      _labSetValuesWindowId = null;
    });
    _showSnackBar('Lab session started');
  }

  void _labOpenWindow() {
    if (!_labActive || !Synheart.isLabAvailable) return;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final label = _labOpenLabelController.text.trim().isEmpty ? null : _labOpenLabelController.text.trim();
    final windowId = Synheart.labOpenWindow(
      windowType: _labOpenWindowType,
      label: label,
      startedAtMs: nowMs,
    );
    if (windowId == null) {
      _showSnackBar('Failed to open window');
      return;
    }
    setState(() {
      _openWindowIds.add(windowId);
      _labSelectedWindowId = windowId;
      _labSetValuesWindowId = windowId;
    });
    _showSnackBar('Opened window: ${label ?? _labOpenWindowType}');
  }

  void _labCloseWindow() {
    final id = _labSelectedWindowId ?? (_openWindowIds.isNotEmpty ? _openWindowIds.first : null);
    if (id == null) {
      _showSnackBar('No window selected');
      return;
    }
    final endMs = DateTime.now().millisecondsSinceEpoch;
    Synheart.labCloseWindow(id, endMs);
    setState(() {
      _openWindowIds.remove(id);
      _labSelectedWindowId = _openWindowIds.isNotEmpty ? _openWindowIds.first : null;
      _labSetValuesWindowId = _openWindowIds.isNotEmpty ? _openWindowIds.first : null;
    });
    _showSnackBar('Closed window');
  }

  void _labSetWindowValues() {
    final id = _labSetValuesWindowId ?? (_openWindowIds.isNotEmpty ? _openWindowIds.first : null);
    if (id == null) {
      _showSnackBar('No window selected');
      return;
    }
    final valuesStr = _labSetValuesController.text.trim();
    if (valuesStr.isEmpty) {
      _showSnackBar('Enter JSON values');
      return;
    }
    try {
      jsonDecode(valuesStr);
    } catch (_) {
      _showSnackBar('Invalid JSON');
      return;
    }
    Synheart.labSetWindowValues(id, valuesStr);
    _showSnackBar('Set window values');
  }

  void _labFinalize() {
    if (!_labActive || !Synheart.isLabAvailable) return;
    final endMs = DateTime.now().millisecondsSinceEpoch;
    final payload = Synheart.labFinalize(endMs);
    setState(() {
      _labActive = false;
      _openWindowIds.clear();
      _labSelectedWindowId = null;
      _labSetValuesWindowId = null;
      _labResultJson = payload;
    });
    if (payload != null) {
      try {
        final parsed = jsonDecode(payload);
        final windows = parsed['windows'] as List?;
        _showSnackBar('Lab finalized: ${windows?.length ?? 0} windows');
      } catch (_) {
        _showSnackBar('Lab finalized');
      }
    } else {
      _showSnackBar('Lab finalize returned null');
    }
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
