import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    NotificationService.instance.requestPermission();
  }

  void go(int i) => setState(() => _i = i);

  @override
  Widget build(BuildContext context) {
    final pages = [HomePage(go: go), const MedicinesPage(), const VisitsPage(), const PharmacyPage(), const SettingsPage()];
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _i, children: pages),
      bottomNavigationBar: BottomBar(index: _i, onTap: go, items: [
        (Icons.home, 'হোম'), (Icons.medication, 'ওষুধ'), (Icons.medical_services, 'ভিজিট'),
        (Icons.storefront, 'ফার্মেসি'), (Icons.settings, 'সেটিংস'),
      ]),
    );
  }
}
