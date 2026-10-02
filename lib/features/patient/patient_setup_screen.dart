import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets.dart';
import '../../services/app_state.dart';
import '../../services/backup_service.dart';
import 'member_form.dart';

/// First-run on a phone with no local data: create the user's own profile, or bring back
/// an earlier Drive backup (health data lives on the phone, so a reinstall starts empty).
class PatientSetupScreen extends StatefulWidget {
  const PatientSetupScreen({super.key});
  @override
  State<PatientSetupScreen> createState() => _PatientSetupScreenState();
}

class _PatientSetupScreenState extends State<PatientSetupScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final ok = await BackupService.instance.restoreLatest();
      if (!mounted) return;
      if (ok) {
        await context.read<AppState>().refresh();
      } else {
        context.toast('Drive-এ কোনো ব্যাকআপ পাওয়া যায়নি');
      }
    } catch (e) {
      if (mounted) context.toast('রিস্টোর হয়নি: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(children: [
        const MemberForm(isSelf: true, setup: true),
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 76),
              child: Material(
                color: Colors.transparent,
                child: TextButton.icon(
                  onPressed: _busy ? null : _restore,
                  icon: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cloud_download),
                  label: const Text('আগে ব্যাকআপ নিয়েছিলেন? Drive থেকে ফিরিয়ে আনুন'),
                ),
              ),
            ),
          ),
        ),
      ]);
}
