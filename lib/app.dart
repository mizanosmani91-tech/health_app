import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/role_screen.dart';
import 'features/owner/owner_register_screen.dart';
import 'features/owner/owner_shell.dart';
import 'features/patient/patient_setup_screen.dart';
import 'features/patient/patient_shell.dart';
import 'services/app_state.dart';
import 'services/auth_service.dart';
import 'services/prefs.dart';

class HealthApp extends StatelessWidget {
  const HealthApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = s.role == UserRole.owner ? Palette.owner : Palette.patient;
    return MaterialApp(
      title: 'স্বাস্থ্য ডায়েরি',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(pal),
      builder: (c, child) => PaletteScope(palette: pal, child: LockGate(child: child!)),
      home: switch (s.stage) {
        Stage.loading => const Scaffold(body: Center(child: CircularProgressIndicator())),
        Stage.onboarding => const OnboardingScreen(),
        Stage.login => const LoginScreen(),
        Stage.pickRole => const RoleScreen(),
        Stage.patientSetup => const PatientSetupScreen(),
        Stage.ownerSetup => const OwnerRegisterScreen(),
        Stage.patient => const PatientShell(),
        Stage.owner => const OwnerShell(),
      },
    );
  }
}

/// Asks for fingerprint / PIN when the app lock is on, on launch and on resume.
class LockGate extends StatefulWidget {
  final Widget child;
  const LockGate({super.key, required this.child});
  @override
  State<LockGate> createState() => _LockGateState();
}

class _LockGateState extends State<LockGate> with WidgetsBindingObserver {
  bool _locked = Prefs.appLock;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.paused && Prefs.appLock) setState(() => _locked = true);
    if (st == AppLifecycleState.resumed && _locked) _unlock();
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: 'স্বাস্থ্য ডায়েরি খুলতে নিশ্চিত করুন');
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Device has no screen lock configured: don't lock the user out of their own data.
      if (mounted) setState(() => _locked = false);
    } finally {
      _asking = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: Material(
              color: context.pal.bg,
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock, size: 56, color: context.pal.primaryDark),
                  const SizedBox(height: 16),
                  const Text('অ্যাপ লক করা আছে', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _unlock, child: const Text('খুলুন')),
                ]),
              ),
            ),
          ),
      ]);
}
