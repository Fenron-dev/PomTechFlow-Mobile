import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_lock_service.dart';

/// Full-screen PIN entry shown when the App-Lock is active.
///
/// The caller receives [onUnlocked] and must handle state transitions.
class AppLockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const AppLockScreen({super.key, required this.onUnlocked});

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _pin = '';
  bool _showRecovery = false;
  String _recoveryInput = '';
  String? _error;
  bool _biometricAvailable = false;

  // Rate-limiting
  DateTime? _lockedUntil;
  int _secondsLeft = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
    _checkLockout();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockout() async {
    final until = await AppLockService.getLockoutEnd();
    if (until != null && mounted) {
      setState(() {
        _lockedUntil = until;
        _secondsLeft = until.difference(DateTime.now()).inSeconds.clamp(0, 9999);
      });
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final left = (_lockedUntil?.difference(DateTime.now()).inSeconds ?? 0).clamp(0, 9999);
      setState(() => _secondsLeft = left);
      if (left <= 0) {
        t.cancel();
        setState(() { _lockedUntil = null; _error = null; });
      }
    });
  }

  Future<void> _initBiometrics() async {
    final ok = await AppLockService.canUseBiometrics();
    if (mounted) setState(() => _biometricAvailable = ok);
    if (ok) _tryBiometrics();
  }

  Future<void> _tryBiometrics() async {
    final ok = await AppLockService.authenticateWithBiometrics();
    if (ok && mounted) widget.onUnlocked();
  }

  void _onDigit(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length >= 4) _checkPin();
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _checkPin() async {
    if (_lockedUntil != null) return; // blocked while locked out
    await Future.delayed(const Duration(milliseconds: 150));
    final ok = await AppLockService.verifyPIN(_pin);
    if (ok) {
      widget.onUnlocked();
    } else {
      final until = await AppLockService.recordFailedAttempt();
      if (!mounted) return;
      if (until != null) {
        final secs = until.difference(DateTime.now()).inSeconds.clamp(0, 9999);
        setState(() {
          _lockedUntil = until;
          _secondsLeft = secs;
          _error = null;
          _pin = '';
        });
        _startCountdown();
      } else {
        setState(() {
          _error = 'Falscher PIN. Biometrie oder Recovery-Code nutzen.';
          _pin = '';
        });
      }
    }
  }

  Future<void> _checkRecovery() async {
    final ok = await AppLockService.verifyRecoveryCode(_recoveryInput);
    if (ok && mounted) {
      // Disable lock so user can set a new PIN in settings
      await AppLockService.disable();
      widget.onUnlocked();
    } else if (mounted) {
      setState(() => _error = 'Falscher Recovery-Code.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: _showRecovery ? _buildRecoveryView(cs) : _buildPinView(cs),
      ),
    );
  }

  // ── PIN-Pad ──────────────────────────────────────────────────────────────

  Widget _buildPinView(ColorScheme cs) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.primary),
            const SizedBox(height: 16),
            Text('PomTechFlow entsperren',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 32),
            // PIN dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(6, (i) {
                final filled = i < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? cs.primary : cs.outlineVariant,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            if (_lockedUntil != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Zu viele Fehlversuche. Noch $_secondsLeft Sekunden gesperrt.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.error, fontSize: 13)),
              ),
            const SizedBox(height: 24),
            // Number pad – disabled while locked out
            IgnorePointer(
              ignoring: _lockedUntil != null,
              child: Opacity(
                opacity: _lockedUntil != null ? 0.35 : 1.0,
                child: _NumberPad(onDigit: _onDigit, onDelete: _onDelete),
              ),
            ),
            const SizedBox(height: 16),
            // Biometrics
            if (_biometricAvailable)
              TextButton.icon(
                onPressed: _tryBiometrics,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Biometrie nutzen'),
              ),
            TextButton(
              onPressed: () => setState(() {
                _showRecovery = true;
                _error = null;
              }),
              child: const Text('PIN vergessen?'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recovery ─────────────────────────────────────────────────────────────

  Widget _buildRecoveryView(ColorScheme cs) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.key_outlined, size: 48, color: cs.primary),
              const SizedBox(height: 16),
              Text('Recovery-Code eingeben',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'Gib den 8-stelligen Recovery-Code ein, den du beim Einrichten des PIN notiert hast. Die App-Sperre wird anschließend deaktiviert.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 24),
              TextField(
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                decoration: InputDecoration(
                  labelText: 'Recovery-Code',
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  counterText: '',
                ),
                onChanged: (v) => setState(() {
                  _recoveryInput = v;
                  _error = null;
                }),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _recoveryInput.length >= 8 ? _checkRecovery : null,
                child: const Text('Entsperren'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _showRecovery = false;
                  _error = null;
                }),
                child: const Text('Zurück zur PIN-Eingabe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Number Pad ─────────────────────────────────────────────────────────────

class _NumberPad extends StatelessWidget {
  final void Function(String) onDigit;
  final VoidCallback onDelete;

  const _NumberPad({required this.onDigit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final digits = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '⌫'];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      childAspectRatio: 1.6,
      children: digits.map((d) {
        if (d.isEmpty) return const SizedBox();
        return Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => d == '⌫' ? onDelete() : onDigit(d),
              child: Center(
                child: Text(
                  d,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: d == '⌫' ? cs.error : cs.onSurface,
                      ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
