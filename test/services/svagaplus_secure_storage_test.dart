import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';
import 'package:donaton_timer/services/svagaplus_credential_store.dart';

class MemorySecrets implements SvagaPlusSecretStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test(
    'credentials write, read, and delete through the secure backend',
    () async {
      final store = SvagaPlusCredentialStore(storage: MemorySecrets());
      const credentials = SvagaPlusCredentials(
        deviceId: 'device-1',
        token: 'secret',
      );

      await store.save(credentials);
      expect((await store.load())?.deviceId, 'device-1');
      expect(credentials.toString(), isNot(contains('secret')));

      await store.clear();
      expect(await store.load(), isNull);
    },
  );

  test('secure storage errors are typed without exposing the token', () async {
    final store = SvagaPlusCredentialStore(storage: _FailingSecrets());
    expect(
      () => store.save(
        const SvagaPlusCredentials(deviceId: 'device-1', token: 'secret'),
      ),
      throwsA(isA<SvagaPlusCredentialException>()),
    );
  });
}

class _FailingSecrets implements SvagaPlusSecretStorage {
  @override
  Future<String?> read(String key) => Future.error('secret');

  @override
  Future<void> write(String key, String value) => Future.error('secret');

  @override
  Future<void> delete(String key) => Future.error('secret');
}
