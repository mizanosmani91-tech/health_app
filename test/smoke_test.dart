import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_app/features/owner/owner_ctx.dart';
import 'package:health_app/features/owner/stock_page.dart';
import 'package:health_app/services/notification_service.dart';
import 'package:provider/provider.dart';

/// Guards for mistakes that already reached a real phone once. Each test names the incident it prevents.
void main() {
  testWidgets('owner pages opened with pushOwner can read OwnerCtx (was: grey blank page on stock "+")', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => OwnerCtx(),
      child: MaterialApp(
        home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => c.pushOwner(const StockFormPage()), child: const Text('open')))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('ওষুধ যোগ'), findsWidgets);
  });

  test('a plain context.push of an owner page would lose the provider (source guard)', () {
    for (final f in Directory('lib/features/owner').listSync().whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      expect(RegExp(r'context\.push\(').hasMatch(src), isFalse, reason: '${f.path}: use context.pushOwner(...) for owner pages');
    }
  });

  test('notification init failure must never stop the app (was: white screen on launch)', () async {
    // No Android plugin in unit tests, so initialize() fails; init() must swallow that and report it.
    await NotificationService.instance.init(); // must complete without throwing
  });

  test('notification small icon is a plain drawable that survives resource shrinking (was: invalid icon)', () {
    final svc = File('lib/services/notification_service.dart').readAsStringSync();
    expect(svc.contains("AndroidInitializationSettings('ic_stat_notify')"), isTrue);
    expect(File('android/app/src/main/res/drawable/ic_stat_notify.xml').existsSync(), isTrue);
    expect(File('android/app/src/main/res/raw/keep.xml').readAsStringSync().contains('ic_stat_notify'), isTrue);
  });

  test('manifest keeps the permissions dose reminders depend on', () {
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    for (final p in ['POST_NOTIFICATIONS', 'SCHEDULE_EXACT_ALARM', 'RECEIVE_BOOT_COMPLETED', 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS']) {
      expect(m.contains(p), isTrue, reason: 'missing $p');
    }
    expect(m.contains('ScheduledNotificationBootReceiver'), isTrue);
  });
}
