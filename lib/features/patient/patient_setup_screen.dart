import 'package:flutter/material.dart';
import 'member_form.dart';

/// First-run: create the user's own profile (no back button, nothing to go back to).
class PatientSetupScreen extends StatelessWidget {
  const PatientSetupScreen({super.key});
  @override
  Widget build(BuildContext context) => const MemberForm(isSelf: true, setup: true);
}
