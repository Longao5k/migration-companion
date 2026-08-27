import 'package:shared_preferences/shared_preferences.dart';

import 'local_repository_base.dart';

LocalRepository createLocalRepository() => WebLocalRepository();

class WebLocalRepository implements LocalRepository {
  @override
  Future<String?> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.get(key);
    return value?.toString();
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(key);
  }
}
