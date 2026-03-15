import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart'
    hide AppSettings;
import '../../providers/settings_provider.dart' as sp;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (settings) => _SettingsForm(settings: settings),
      ),
    );
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  final sp.AppSettings settings;
  const _SettingsForm({required this.settings});

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final TextEditingController _companyCtrl;
  late final TextEditingController _techCtrl;
  late int _aeMinutes;
  late int _pomodoroMinutes;
  late int _shortBreakMinutes;
  late int _longBreakMinutes;

  @override
  void initState() {
    super.initState();
    _companyCtrl = TextEditingController(text: widget.settings.companyName);
    _techCtrl = TextEditingController(text: widget.settings.technicianName);
    _aeMinutes = widget.settings.aeMinutes;
    _pomodoroMinutes = widget.settings.pomodoroMinutes;
    _shortBreakMinutes = widget.settings.shortBreakMinutes;
    _longBreakMinutes = widget.settings.longBreakMinutes;
  }

  @override
  void dispose() {
    _companyCtrl.dispose();
    _techCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsProvider.notifier).save(
          widget.settings.copyWith(
            companyName: _companyCtrl.text.trim(),
            technicianName: _techCtrl.text.trim(),
            aeMinutes: _aeMinutes,
            pomodoroMinutes: _pomodoroMinutes,
            shortBreakMinutes: _shortBreakMinutes,
            longBreakMinutes: _longBreakMinutes,
          ),
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einstellungen gespeichert')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionHeader('Firma'),
        TextField(
          controller: _companyCtrl,
          decoration: const InputDecoration(labelText: 'Firmenname'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _techCtrl,
          decoration: const InputDecoration(labelText: 'Techniker Name'),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Arbeitseinheiten (AE)'),
        _StepperField(
          label: 'Minuten pro AE',
          value: _aeMinutes,
          min: 1,
          max: 60,
          onChanged: (v) => setState(() => _aeMinutes = v),
        ),
        const SizedBox(height: 24),

        _SectionHeader('Timer'),
        _StepperField(
          label: 'Fokuszeit (Minuten)',
          value: _pomodoroMinutes,
          min: 1,
          max: 120,
          onChanged: (v) => setState(() => _pomodoroMinutes = v),
        ),
        const SizedBox(height: 12),
        _StepperField(
          label: 'Kurze Pause (Minuten)',
          value: _shortBreakMinutes,
          min: 1,
          max: 30,
          onChanged: (v) => setState(() => _shortBreakMinutes = v),
        ),
        const SizedBox(height: 12),
        _StepperField(
          label: 'Lange Pause (Minuten)',
          value: _longBreakMinutes,
          min: 1,
          max: 60,
          onChanged: (v) => setState(() => _longBreakMinutes = v),
        ),
        const SizedBox(height: 32),

        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save),
          label: const Text('Speichern'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _StepperField extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _StepperField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toString(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }
}
