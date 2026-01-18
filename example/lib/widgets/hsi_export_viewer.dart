import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:synheart_core/synheart_core.dart';
import 'dart:convert';

/// HSI export viewer widget
class HSIExportViewer extends StatelessWidget {
  final HumanStateVector? hsv;

  const HSIExportViewer({super.key, this.hsv});

  @override
  Widget build(BuildContext context) {
    if (hsv == null) {
      return const Center(
        child: Text('No HSV data available'),
      );
    }

    try {
      final hsi10 = hsv!.toHSI10(
        producerName: 'Synheart Example App',
        producerVersion: '1.0.0',
        instanceId: 'example-instance-${DateTime.now().millisecondsSinceEpoch}',
      );

      final json = hsi10.toJson();
      final jsonString = JsonEncoder.withIndent('  ').convert(json);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'HSI 1.0 Export',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy to clipboard',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: jsonString));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('HSI JSON copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  jsonString,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Failed to export HSI',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              e.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }
}

