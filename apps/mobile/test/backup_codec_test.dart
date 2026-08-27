import 'package:flutter_test/flutter_test.dart';
import 'package:migration_companion/core/backup/backup_codec.dart';

void main() {
  test('encrypted backup round-trips without plaintext leakage', () async {
    const payload = <String, Object?>{
      'schema': 'migration-companion-backup/v1',
      'project': <String, Object?>{'name': '私密南澳项目'},
    };
    final encrypted = await BackupCodec.encrypt(
      payload,
      'correct horse battery staple',
    );
    final encodedEnvelope = String.fromCharCodes(encrypted);

    expect(encodedEnvelope, isNot(contains('私密南澳项目')));
    expect(
      await BackupCodec.decrypt(encrypted, 'correct horse battery staple'),
      payload,
    );
  });

  test('wrong backup password is rejected', () async {
    final encrypted = await BackupCodec.encrypt(const <String, Object?>{
      'schema': 'migration-companion-backup/v1',
    }, 'correct horse battery staple');

    await expectLater(
      BackupCodec.decrypt(encrypted, 'wrong password is long'),
      throwsA(isA<FormatException>()),
    );
  });
}
