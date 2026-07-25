import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
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
  final acknowledgements = <(String, int)>[];
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
  void acknowledge(String eventId, int cursor) {
    acknowledgements.add((eventId, cursor));
  }

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
      final event = SvagaPlusSubscriptionEvent.fromJson({
        'id': 'event-7',
        'cursor': 7,
        'event_type': 'new_subscription',
        'subscriber_name': 'Alice',
        'created_at': DateTime.utc(2026, 7, 25).toIso8601String(),
      });
      adapter.acknowledge(event);
      storedCursor = 7;
      sockets.single.disconnectedController.add(null);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(sockets.last.constructedCursor, 7);
      expect(sockets.first.acknowledgements, [('event-7', 7)]);
      await adapter.dispose();
    },
  );

  test('does not republish a live event after it is acknowledged', () async {
    final socket = AdapterSocket();
    final delivered = <SvagaPlusSubscriptionEvent>[];
    final adapter = SvagaPlusAdapter(
      api: AdapterApi(),
      credentials: const SvagaPlusCredentials(deviceId: 'd', token: 't'),
      lastCursor: 1,
      appVersion: 'test',
      socketFactory:
          ({required credentials, required lastCursor, required appVersion}) =>
              socket,
    );
    final subscription = adapter.events.listen(delivered.add);

    adapter.start();
    await Future<void>.delayed(Duration.zero);
    socket.readyController.add({'high_watermark': 1});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final event = SvagaPlusSubscriptionEvent.fromJson({
      'id': 'event-7',
      'cursor': 7,
      'event_type': 'new_subscription',
      'subscriber_name': 'Alice',
      'created_at': DateTime.utc(2026, 7, 25).toIso8601String(),
    });

    adapter.acknowledge(event);
    socket.eventController.add(event.toJson());
    await Future<void>.delayed(Duration.zero);

    expect(delivered, isEmpty);
    await subscription.cancel();
    await adapter.dispose();
  });
}
