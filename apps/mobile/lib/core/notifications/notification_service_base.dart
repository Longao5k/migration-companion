abstract interface class NotificationService {
  Future<void> schedule({
    required String stableId,
    required DateTime at,
    required String payload,
  });

  Future<void> cancel(String stableId);
}

int notificationIdFor(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash;
}
