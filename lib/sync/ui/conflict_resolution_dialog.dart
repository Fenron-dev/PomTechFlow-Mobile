import 'package:flutter/material.dart';

class ConflictResolutionDialog extends StatelessWidget {
  final List<Map<String, dynamic>> conflicts;
  final VoidCallback onDismiss;

  const ConflictResolutionDialog({
    super.key,
    required this.conflicts,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(children: [
        Icon(Icons.warning_amber_outlined, color: Colors.orange),
        SizedBox(width: 8),
        Text('Sync-Konflikte'),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${conflicts.length} Datensatz(Datensätze) wurde(n) zwischenzeitlich auf dem Server geändert.',
            ),
            const SizedBox(height: 12),
            Text(
              'Die Server-Version wurde beibehalten (Last-Write-Wins). '
              'Falls du eine andere Version bevorzugst, bearbeite den Datensatz erneut.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: conflicts.length,
                itemBuilder: (ctx, i) {
                  final c = conflicts[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.sync_problem, size: 18),
                    title: Text('${c['table']} / ${c['id']}',
                        style: const TextStyle(fontSize: 12)),
                    subtitle: Text(
                      'Server: ${c['serverModifiedAt'] ?? '–'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: onDismiss,
          child: const Text('Verstanden'),
        ),
      ],
    );
  }
}
