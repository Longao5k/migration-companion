import 'notification_service_base.dart';

NotificationService createPlatformNotificationService() =>
    WebNotificationService();

class WebNotificationService implements NotificationService {
  @override
  Future<void> cancel(String stableId) async {}

  @override
  Future<void> schedule({
    required String stableId,
    required DateTime at,
    required String payload,
  }) => throw const FormatException('网页预览不能可靠安排系统提醒；请使用 Android 或 iPhone App');
}
