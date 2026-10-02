import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'data/local_db.dart';
import 'services/app_state.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'services/prefs.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await LocalDb.instance.init();
  try {
    await NotificationService.instance.init();
    await AuthService.init();
  } catch (e) {
    debugPrint('startup service init failed: $e'); // the app must still open
  }
  final state = AppState()..start();
  runApp(ChangeNotifierProvider.value(value: state, child: const HealthApp()));
}
