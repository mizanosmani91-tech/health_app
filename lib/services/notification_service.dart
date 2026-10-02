import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../core/bn.dart';
import '../data/local_db.dart';
import 'prefs.dart';

/// Local (offline) reminders: dose alarms, running-out alerts, visit/test reminders.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _slots = ['morning', 'noon', 'night'];
  static const _slotNames = {'morning': 'সকালের', 'noon': 'দুপুরের', 'night': 'রাতের'};
  static const _windowDays = 14; // days scheduled ahead; the app re-schedules every time it opens
  static const _maxAlarms = 420; // Android allows ~500 pending alarms per app; nearest ones win

  Future<void> init() async {
    if (kIsWeb) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Dhaka'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
    );
    _ready = true;
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final a = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await a?.requestNotificationsPermission() ?? true;
  }

  NotificationDetails _details(String channel, String name) => NotificationDetails(
        android: AndroidNotificationDetails(channel, name,
            importance: Importance.max, priority: Priority.max, category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public, enableVibration: true, playSound: true,
            styleInformation: const BigTextStyleInformation('')));

  bool _exactOk = true;

  /// Exact alarms fire on time even in Doze; if the user denied that permission we fall back to
  /// "inexact" (may be a few minutes late) rather than not reminding at all.
  Future<void> _schedule(_Alarm a) async {
    final when = tz.TZDateTime.from(a.when, tz.local);
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: a.id, scheduledDate: when, notificationDetails: _details(a.channel, a.channelName),
          androidScheduleMode: mode, title: a.title, body: a.body);
    if (_exactOk) {
      try {
        return await go(AndroidScheduleMode.exactAllowWhileIdle);
      } catch (_) {
        _exactOk = false;
      }
    }
    await go(AndroidScheduleMode.inexactAllowWhileIdle);
  }

  /// Cancels everything and schedules the next [_windowDays] days from the current data.
  Future<void> rescheduleAll() async {
    if (!_ready) return;
    await _plugin.cancelAll();
    if (!Prefs.remindersOn) return;
    _exactOk = await Permission.scheduleExactAlarm.isGranted;
    final db = LocalDb.instance;
    final members = {for (final m in await db.members()) m.id!: m};
    final today = dateOnly(DateTime.now());
    final alarms = <_Alarm>[];
    void add(int id, DateTime when, String title, String body, String ch, String chName) {
      if (when.isAfter(DateTime.now())) alarms.add(_Alarm(id, when, title, body, ch, chName));
    }

    for (final med in await db.medicines()) {
      if (!med.active) continue;
      final who = members[med.memberId]?.name ?? '';
      for (var d = 0; d < _windowDays; d++) {
        final day = today.add(Duration(days: d));
        if (day.isAfter(med.lastDay) || day.isBefore(dateOnly(med.startDate))) continue;
        final on = [med.morning, med.noon, med.night];
        for (var s = 0; s < 3; s++) {
          if (!on[s]) continue;
          add(med.id! * 100 + d * 3 + s, day.add(Duration(minutes: Prefs.slotMinutes(_slots[s]))),
              '${_slotNames[_slots[s]]} ওষুধ · $who', '${med.name} ${med.mealLabel}'.trim(), 'doses', 'ওষুধের সময়');
        }
      }
      // Running-out alert: 3 days before the last bought day, at 9 am.
      add(8000000 + med.id!, med.lastDay.subtract(const Duration(days: 3)).add(const Duration(hours: 9)),
          '${med.name} প্রায় শেষ', '$who · আর ${bn(3)} দিনের ওষুধ আছে, কিনুন', 'stock', 'ওষুধ শেষের সতর্কতা');
    }
    for (final v in await db.allVisits()) {
      if (v.nextVisit == null) continue;
      final who = members[v.memberId]?.name ?? '';
      add(9000000 + v.id!, v.nextVisit!.subtract(const Duration(days: 1)).add(const Duration(hours: 9)),
          'কাল ডাক্তারের কাছে যেতে হবে', '$who · ${v.doctor.isEmpty ? v.place : v.doctor}', 'visits', 'ভিজিট রিমাইন্ডার');
    }
    for (final t in await db.allTests()) {
      if (t.dueDate == null || t.doneDate != null) continue;
      final who = members[t.memberId]?.name ?? '';
      add(9500000 + t.id!, t.dueDate!.subtract(const Duration(days: 1)).add(const Duration(hours: 9)),
          'কাল টেস্ট করাতে হবে', '$who · ${t.name}', 'tests', 'টেস্ট রিমাইন্ডার');
    }
    // Safety net: reminders only exist for the next two weeks, so ask the person to open the app before they run out.
    if (alarms.any((a) => a.channel == 'doses')) {
      add(9900000, today.add(const Duration(days: _windowDays - 2, hours: 9)),
          'রিমাইন্ডার চালু রাখতে অ্যাপটি একবার খুলুন', 'না খুললে কয়েকদিন পর ওষুধের রিমাইন্ডার বন্ধ হয়ে যাবে', 'stock', 'ওষুধ শেষের সতর্কতা');
    }
    alarms.sort((a, b) => a.when.compareTo(b.when));
    for (final a in alarms.take(_maxAlarms)) {
      await _schedule(a);
    }
  }

  /// For the "check my reminders" screen.
  Future<ReminderHealth> health() async => ReminderHealth(
        notifications: await Permission.notification.isGranted,
        exactAlarms: await Permission.scheduleExactAlarm.isGranted,
        batteryUnrestricted: await Permission.ignoreBatteryOptimizations.isGranted,
        pending: _ready ? (await _plugin.pendingNotificationRequests()).length : 0,
      );

  Future<void> askNotifications() => Permission.notification.request();
  Future<void> askExactAlarms() => Permission.scheduleExactAlarm.request();
  Future<void> askBattery() => Permission.ignoreBatteryOptimizations.request();

  /// Shows a notification immediately: proves the permission, channel and icon work (separate from alarms).
  Future<void> showNow() => _plugin.show(
        id: 9999998, title: 'পরীক্ষা: নোটিফিকেশন কাজ করছে', body: 'এখন ১ মিনিট পরের রিমাইন্ডারের জন্য অপেক্ষা করুন',
        notificationDetails: _details('doses', 'ওষুধের সময়'));

  /// Fires one real reminder through the same path as dose alarms, [seconds] from now.
  Future<void> sendTest({int seconds = 60}) async {
    _exactOk = await Permission.scheduleExactAlarm.isGranted;
    await _schedule(_Alarm(9999999, DateTime.now().add(Duration(seconds: seconds)), 'পরীক্ষা: রিমাইন্ডার ঠিকমতো কাজ করছে',
        'এভাবেই ওষুধের সময় জানানো হবে', 'doses', 'ওষুধের সময়'));
  }
}

class _Alarm {
  final int id;
  final DateTime when;
  final String title, body, channel, channelName;
  _Alarm(this.id, this.when, this.title, this.body, this.channel, this.channelName);
}

class ReminderHealth {
  final bool notifications, exactAlarms, batteryUnrestricted;
  final int pending;
  const ReminderHealth({required this.notifications, required this.exactAlarms, required this.batteryUnrestricted, required this.pending});
  bool get allGood => notifications && exactAlarms && batteryUnrestricted;
}
