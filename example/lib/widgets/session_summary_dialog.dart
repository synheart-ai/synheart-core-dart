import 'package:flutter/material.dart';

/// Dialog that shows a summary of the last captured HSI
/// state after a session is stopped.
class SessionSummaryDialog extends StatelessWidget {
  final String? hsiJson;

  const SessionSummaryDialog({
    super.key,
    this.hsiJson,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Session Summary'),
      content: hsiJson != null
          ? SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Last HSI JSON:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      hsiJson!,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'Courier',
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No data captured during this session',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
