import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';

void main() {
  const credentials = SvagaPlusCredentials(
    deviceId: 'device-1',
    token: 'token-1',
  );

  test('pairing start sends only the device name', () async {
    late http.Request request;
    final client = SvagaPlusApiClient(
      baseUri: Uri.parse('https://example.test'),
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'data': {
              'pairing_id': 'pairing',
              'user_code': '1234-5678',
              'pairing_secret': 'pair-secret',
              'expires_at': '2026-07-20T14:30:00Z',
            },
          }),
          200,
        );
      }),
    );

    await client.startPairing(deviceName: 'Streaming PC');
    expect(jsonDecode(request.body), {'device_name': 'Streaming PC'});
  });

  test('device endpoints use TimerDevice authorization', () async {
    late http.Request request;
    final client = SvagaPlusApiClient(
      baseUri: Uri.parse('https://example.test'),
      client: MockClient((value) async {
        request = value;
        return http.Response(
          jsonEncode({
            'data': {'high_watermark': 4},
          }),
          200,
        );
      }),
    );

    expect(await client.getHead(credentials), 4);
    expect(request.headers['authorization'], 'TimerDevice device-1:token-1');
  });

  test('event pages are parsed in ascending cursor order', () async {
    final client = SvagaPlusApiClient(
      baseUri: Uri.parse('https://example.test'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'events': [
                {
                  'id': 'event-2',
                  'cursor': 2,
                  'event_type': 'renewed_subscription',
                  'subscriber_name': 'B',
                  'created_at': '2026-07-20T14:30:00Z',
                },
                {
                  'id': 'event-1',
                  'cursor': 1,
                  'event_type': 'new_subscription',
                  'subscriber_name': 'A',
                  'created_at': '2026-07-20T14:29:00Z',
                },
              ],
              'next_cursor': 2,
              'has_more': false,
            },
          }),
          200,
        ),
      ),
    );

    final page = await client.getEvents(credentials, after: 0, until: 2);
    expect(page.events.map((event) => event.cursor), [1, 2]);
    expect(page.events.first.eventType, SvagaPlusEventType.newSubscription);
  });

  test('401 and malformed JSON map to typed errors', () async {
    final unauthorized = SvagaPlusApiClient(
      baseUri: Uri.parse('https://example.test'),
      client: MockClient((_) async => http.Response('', 401)),
    );
    expect(
      unauthorized.getHead(credentials),
      throwsA(isA<SvagaPlusAuthorizationException>()),
    );

    final malformed = SvagaPlusApiClient(
      baseUri: Uri.parse('https://example.test'),
      client: MockClient((_) async => http.Response('{', 200)),
    );
    expect(
      malformed.getHead(credentials),
      throwsA(isA<SvagaPlusProtocolException>()),
    );
  });

  test('release configuration rejects insecure base URLs', () {
    expect(
      () => SvagaPlusApiClient(
        baseUri: Uri.parse('http://example.test'),
        allowInsecureTransport: false,
      ),
      throwsArgumentError,
    );
  });
}
