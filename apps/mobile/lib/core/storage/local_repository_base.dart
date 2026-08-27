abstract interface class LocalRepository {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}
