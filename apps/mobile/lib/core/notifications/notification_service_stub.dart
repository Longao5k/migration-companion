import 'notification_service_base.dart';

NotificationService createPlatformNotificationService() =>
    StubNotificationService();

class StubNotificationService implements NotificationService {
  @override
  Future<void> cancel(String stableId) async {}

  @override
  Future<void> schedule({
    required String stableId,
    required DateTime at,
    required String payload,
  }) async {}
}
