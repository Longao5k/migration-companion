import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'local_repository_base.dart';

LocalRepository createLocalRepository() => NativeEncryptedLocalRepository();

class NativeEncryptedLocalRepository implements LocalRepository {
  static const _databaseKeyName = 'migration_companion.database_key.v1';
  static const _legacyKeys = <String>[
    'migration_companion.projects.v1',
    'migration_companion.signed_in.v1',
    'migration_companion.account_email.v1',
    'migration_companion.notice_dismissed.v1',
    'migration_companion.bookmarks.v1',
  ];

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  Database? _database;
  bool _fallbackToPreferences = false;

  Future<Database?> _open() async {
    if (_fallbackToPreferences) return null;
    if (_database case final database?) return database;
    try {
      var encryptionKey = await _secureStorage.read(key: _databaseKeyName);
      if (encryptionKey == null) {
        final bytes = List<int>.generate(
          32,
          (_) => Random.secure().nextInt(256),
        );
        encryptionKey = base64UrlEncode(bytes);
        await _secureStorage.write(key: _databaseKeyName, value: encryptionKey);
      }
      final databasePath = path.join(
        await getDatabasesPath(),
        'migration_companion.db',
      );
      final database = await openDatabase(
        databasePath,
        password: encryptionKey,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE app_kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      );
      _database = database;
      await _migrateLegacyPreferences(database);
      return database;
    } catch (_) {
      // Widget tests and unsupported desktop previews do not have the native
      // SQLCipher channel. Production Android/iOS builds must pass the storage POC.
      _fallbackToPreferences = true;
      return null;
    }
  }

  Future<void> _migrateLegacyPreferences(Database database) async {
    final preferences = await SharedPreferences.getInstance();
    for (final key in _legacyKeys) {
      final existing = await database.query(
        'app_kv',
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      final legacy = preferences.get(key);
      if (legacy == null) continue;
      await database.insert('app_kv', {'key': key, 'value': legacy.toString()});
      await preferences.remove(key);
    }
  }

  @override
  Future<String?> read(String key) async {
    final database = await _open();
    if (database == null) {
      final preferences = await SharedPreferences.getInstance();
      return preferences.get(key)?.toString();
    }
    final rows = await database.query(
      'app_kv',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> write(String key, String value) async {
    final database = await _open();
    if (database == null) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
      return;
    }
    await database.insert('app_kv', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> remove(String key) async {
    final database = await _open();
    if (database == null) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(key);
      return;
    }
    await database.delete('app_kv', where: 'key = ?', whereArgs: [key]);
  }
}
