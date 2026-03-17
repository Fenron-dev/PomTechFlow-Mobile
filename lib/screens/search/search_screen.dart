import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/database_provider.dart';
import '../../db/database.dart';
import 'package:drift/drift.dart' show OrderingTerm;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(tasksProvider);
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Tasks, Kunden suchen…',
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  )
                : null,
          ),
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
      ),
      body: _query.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Suchbegriff eingeben',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : tasksAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Fehler: $e')),
              data: (tasks) => _SearchResults(
                query: _query,
                tasks: tasks,
                db: db,
              ),
            ),
    );
  }
}

class _SearchResults extends ConsumerWidget {
  final String query;
  final List<TaskWithDetails> tasks;
  final AppDatabase db;

  const _SearchResults({
    required this.query,
    required this.tasks,
    required this.db,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchedTasks = tasks.where((t) {
      final title = t.task.title.toLowerCase();
      final customer = t.customer?.name.toLowerCase() ?? '';
      final desc = (t.task.description ?? '').toLowerCase();
      return title.contains(query) ||
          customer.contains(query) ||
          desc.contains(query);
    }).toList();

    final customersAsync = ref.watch(_customersSearchProvider);
    final matchedCustomers = customersAsync.valueOrNull
            ?.where((c) =>
                c.name.toLowerCase().contains(query) ||
                (c.email ?? '').toLowerCase().contains(query) ||
                (c.phone ?? '').toLowerCase().contains(query))
            .toList() ??
        [];

    if (matchedTasks.isEmpty && matchedCustomers.isEmpty) {
      return const Center(
        child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView(
      children: [
        if (matchedTasks.isNotEmpty) ...[
          _SectionHeader('Tasks (${matchedTasks.length})'),
          ...matchedTasks.map((t) => _TaskResult(task: t)),
        ],
        if (matchedCustomers.isNotEmpty) ...[
          _SectionHeader('Kunden (${matchedCustomers.length})'),
          ...matchedCustomers.map((c) => _CustomerResult(customer: c)),
        ],
      ],
    );
  }
}

final _customersSearchProvider = FutureProvider<List<Customer>>((ref) async {
  final db = ref.watch(databaseProvider);
  return (db.select(db.customers)
        ..orderBy([(c) => OrderingTerm(expression: c.name)]))
      .get();
});

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _TaskResult extends StatelessWidget {
  final TaskWithDetails task;
  const _TaskResult({required this.task});

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      'PLANNED': Colors.grey,
      'ACTIVE': Colors.blue,
      'PAUSED': Colors.orange,
      'COMPLETED': Colors.green,
    };
    final statusLabels = {
      'PLANNED': 'Geplant',
      'ACTIVE': 'Aktiv',
      'PAUSED': 'Pausiert',
      'COMPLETED': 'Erledigt',
    };
    final color = statusColors[task.task.status] ?? Colors.grey;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withAlpha(30),
        child: Icon(Icons.task_alt, color: color, size: 20),
      ),
      title: Text(task.task.title),
      subtitle: task.customer != null ? Text(task.customer!.name) : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          statusLabels[task.task.status] ?? task.task.status,
          style: TextStyle(color: color, fontSize: 11),
        ),
      ),
      onTap: () => context.push('/tasks/${task.task.id}'),
    );
  }
}

class _CustomerResult extends StatelessWidget {
  final Customer customer;
  const _CustomerResult({required this.customer});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.business,
            color: Theme.of(context).colorScheme.primary, size: 20),
      ),
      title: Text(customer.name),
      subtitle: customer.email != null
          ? Text(customer.email!)
          : null,
      onTap: () => context.push('/customers'),
    );
  }
}
