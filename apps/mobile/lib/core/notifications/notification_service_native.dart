import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'notification_service_base.dart';

NotificationService createPlatformNotificationService() =>
    NativeNotificationService();

class NativeNotificationService implements NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _initialization;

  Future<void> _initialize() => _initialization ??= _initializeOnce();

  Future<void> _initializeOnce() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<void> schedule({
    required String stableId,
    required DateTime at,
    required String payload,
  }) async {
    if (!at.isAfter(DateTime.now())) throw const FormatException('提醒时间必须晚于现在');
    await _initialize();
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    if (Platform.isIOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
    await _plugin.zonedSchedule(
      id: notificationIdFor(stableId),
      title: '材料提醒',
      body: '你设置的一项申请材料提醒已到时间。打开 App 查看详情。',
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'material-reminders',
          '材料提醒',
          channelDescription: '用户主动设置的材料日期提醒',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: payload,
    );
  }

  @override
  Future<void> cancel(String stableId) async {
    await _initialize();
    await _plugin.cancel(id: notificationIdFor(stableId));
  }
}
