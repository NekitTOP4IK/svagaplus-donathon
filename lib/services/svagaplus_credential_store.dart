import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'svagaplus_api_client.dart';

abstract interface class SvagaPlusSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class _FlutterSecretStorage implements SvagaPlusSecretStorage {
  final FlutterSecureStorage storage;
  const _FlutterSecretStorage(this.storage);

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class SvagaPlusCredentialException implements Exception {
  final String operation;
  final Object cause;
  const SvagaPlusCredentialException(this.operation, this.cause);

  @override
  String toString() => 'SvagaPlusCredentialException($operation)';
}

class SvagaPlusCredentialStore {
  static const deviceIdKey = 'svagaplus.device_id';
  static const deviceTokenKey = 'svagaplus.device_token';

  final SvagaPlusSecretStorage storage;

  SvagaPlusCredentialStore({
    SvagaPlusSecretStorage? storage,
    FlutterSecureStorage? secureStorage,
  }) : storage =
           storage ??
           _FlutterSecretStorage(secureStorage ?? const FlutterSecureStorage());

  Future<void> save(SvagaPlusCredentials credentials) async {
    try {
      await storage.write(deviceIdKey, credentials.deviceId);
      await storage.write(deviceTokenKey, credentials.token);
    } catch (error) {
      throw SvagaPlusCredentialException('save', error);
    }
  }

  Future<void> write(SvagaPlusCredentials credentials) => save(credentials);

  Future<SvagaPlusCredentials?> load() async {
    try {
      final deviceId = await storage.read(deviceIdKey);
      final token = await storage.read(deviceTokenKey);
      if (deviceId == null ||
          token == null ||
          deviceId.isEmpty ||
          token.isEmpty) {
        return null;
      }
      return SvagaPlusCredentials(deviceId: deviceId, token: token);
    } catch (error) {
      throw SvagaPlusCredentialException('load', error);
    }
  }

  Future<SvagaPlusCredentials?> read() => load();

  Future<void> clear() async {
    try {
      await storage.delete(deviceIdKey);
      await storage.delete(deviceTokenKey);
    } catch (error) {
      throw SvagaPlusCredentialException('clear', error);
    }
  }

  Future<void> delete() => clear();
}
