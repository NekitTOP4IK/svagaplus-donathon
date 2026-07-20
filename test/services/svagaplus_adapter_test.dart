import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/services/svagaplus_adapter.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';
import 'package:donaton_timer/services/svagaplus_socket_client.dart';

class AdapterApi extends SvagaPlusApiClient {
  AdapterApi() : super(baseUri: Uri.parse('https://example.test'));
  @override
  Future<SvagaPlusTimerEventPage> getEvents(
    SvagaPlusCredentials credentials, {
    required int after,
    required int until,
    int limit = 100,
  }) async => const SvagaPlusTimerEventPage(
    events: [],
    nextCursor: 0,
    hasMore: false,
    highWatermark: 0,
  );
}

class AdapterSocket implements SvagaPlusSocketTransport {
  final readyController = StreamController<Map<String, dynamic>>.broadcast();
  final eventController = StreamController<Map<String, dynamic>>.broadcast();
  final revokedController = StreamController<void>.broadcast();
  final disconnectedController = StreamController<void>.broadcast();
  int? constructedCursor;
  bool connected = false;

  @override
  Stream<Map<String, dynamic>> get ready => readyController.stream;
  @override
  Stream<Map<String, dynamic>> get events => eventController.stream;
  @override
  Stream<void> get revoked => revokedController.stream;
  @override
  Stream<void> get disconnected => disconnectedController.stream;
  @override
  void connect() => connected = true;
  @override
  void acknowledge(String eventId, int cursor) {}
  @override
  Future<void> dispose() async {
    await readyController.close();
    await eventController.close();
    await revokedController.close();
    await disconnectedController.close();
  }
}

void main() {
  test(
    'reconnect creates socket with cursor freshly loaded from storage',
    () async {
      var storedCursor = 2;
      final sockets = <AdapterSocket>[];
      final adapter = SvagaPlusAdapter(
        api: AdapterApi(),
        credentials: const SvagaPlusCredentials(deviceId: 'd', token: 't'),
        lastCursor: 1,
        appVersion: 'test',
        cursorLoader: () => storedCursor,
        retryDelay: (_) => Duration.zero,
        socketFactory:
            ({required credentials, required lastCursor, required appVersion}) {
              final socket = AdapterSocket()..constructedCursor = lastCursor;
              sockets.add(socket);
              return socket;
            },
      );

      adapter.start();
      await Future<void>.delayed(Duration.zero);
      expect(sockets.single.constructedCursor, 1);
      storedCursor = 9;
      sockets.single.disconnectedController.add(null);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sockets.last.constructedCursor, 9);
      await adapter.dispose();
    },
  );
}
