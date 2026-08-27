import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class BackupCodec {
  static const iterations = 210000;
  static final _cipher = AesGcm.with256bits();
  static final _kdf = Pbkdf2.hmacSha256(iterations: iterations, bits: 256);

  static Future<Uint8List> encrypt(
    Map<String, Object?> payload,
    String password,
  ) async {
    if (password.length < 10) {
      throw const FormatException('备份口令至少需要 10 个字符');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final secretKey = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final clearText = utf8.encode(jsonEncode(payload));
    final box = await _cipher.encrypt(clearText, secretKey: secretKey);
    final envelope = {
      'format': 'migration-companion-backup/v1',
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64UrlEncode(salt),
      'cipher': 'AES-256-GCM',
      'box': base64UrlEncode(box.concatenation()),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  static Future<Map<String, dynamic>> decrypt(
    List<int> bytes,
    String password,
  ) async {
    try {
      final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (envelope['format'] != 'migration-companion-backup/v1' ||
          envelope['iterations'] != iterations ||
          envelope['cipher'] != 'AES-256-GCM') {
        throw const FormatException('不支持的备份格式');
      }
      final salt = base64Url.decode(envelope['salt'] as String);
      final concatenated = base64Url.decode(envelope['box'] as String);
      final secretKey = await _kdf.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );
      final box = SecretBox.fromConcatenation(
        concatenated,
        nonceLength: _cipher.nonceLength,
        macLength: _cipher.macAlgorithm.macLength,
      );
      final clearText = await _cipher.decrypt(box, secretKey: secretKey);
      return jsonDecode(utf8.decode(clearText)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const FormatException('口令错误或备份已损坏');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取此备份');
    }
  }
}
