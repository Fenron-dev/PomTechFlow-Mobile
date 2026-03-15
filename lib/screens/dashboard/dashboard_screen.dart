import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/settings_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksProvider);
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (tasks) {
          final active = tasks.where((t) => t.task.status == 'ACTIVE').length;
          final completed =
              tasks.where((t) => t.task.status == 'COMPLETED').length;
          final planned =
              tasks.where((t) => t.task.status == 'PLANNED').length;
          final totalMinutes =
              tasks.fold<int>(0, (s, t) => s + t.task.totalMinutes);
          final aeMinutes =
              settingsAsync.valueOrNull?.aeMinutes ?? 10;
          final totalAE = totalMinutes / aeMinutes;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Übersicht',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _DashCard(
                    label: 'Aktive Tasks',
                    value: active.toString(),
                    icon: Icons.play_circle_outline,
                    color: Theme.of(context).colorScheme.primaryContainer,
                  ),
                  _DashCard(
                    label: 'Abgeschlossen',
                    value: completed.toString(),
                    icon: Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.secondaryContainer,
                  ),
                  _DashCard(
                    label: 'Geplant',
                    value: planned.toString(),
                    icon: Icons.schedule,
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                  ),
                  _DashCard(
                    label: 'Gesamt AE',
                    value: totalAE.toStringAsFixed(1),
                    icon: Icons.timer_outlined,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (tasks.isNotEmpty) ...[
                Text('Letzte Tasks',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ...tasks.take(5).map((t) => ListTile(
                      title: Text(t.task.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: t.customer != null
                          ? Text(t.customer!.name)
                          : null,
                      trailing: Text(
                        '${t.aeCount.toStringAsFixed(1)} AE',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    )),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DashCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _DashCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24),
          const Spacer(),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
