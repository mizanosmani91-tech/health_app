import 'package:flutter/material.dart';
import 'reminder_check_page.dart';
import '../../services/prefs.dart';
import '../../core/widgets.dart';
import '../../services/notification_service.dart';
import 'home_page.dart';
import 'medicines_page.dart';
import 'pharmacy_page.dart';
import 'settings_page.dart';
import 'visits_page.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({super.key});
  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _i = 0;
  final _history = <int>[]; // tabs visited before this one, so Back returns to the previous page

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermission();
    // First time only: walk the person through the reminder settings (home keeps a warning card afterwards).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (Prefs.reminderWizardSeen || !mounted) return;
      final h = await NotificationService.instance.health();
      if (h.allGood || !mounted) return;
      Prefs.reminderWizardSeen = true;
      context.push(const ReminderCheckPage());
    });
  }

  void go(int i) {
    if (i == _i) return;
    setState(() { _history.add(_i); _i = i; });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [HomePage(go: go), const MedicinesPage(), const VisitsPage(), const PharmacyPage(), const SettingsPage()];
    return PopScope(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _history.isNotEmpty) setState(() => _i = _history.removeLast());
      },
      child: Scaffold(
      extendBody: true,
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: BottomBar(index: _i, onTap: go, items: [
        (Icons.home, 'হোম'), (Icons.medication, 'ওষুধ'), (Icons.medical_services, 'ভিজিট'),
        (Icons.storefront, 'ফার্মেসি'), (Icons.settings, 'সেটিংস'),
      ]),
    ));
  }
}
