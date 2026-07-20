import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/svagaplus_subscription_event.dart';

class SvagaPlusCredentials {
  final String deviceId;
  final String token;
  const SvagaPlusCredentials({required this.deviceId, required this.token});

  @override
  String toString() => 'SvagaPlusCredentials(deviceId: $deviceId, token: ***)';
}

class SvagaPlusAuthorizationException implements Exception {
  final int statusCode;
  const SvagaPlusAuthorizationException([this.statusCode = 401]);

  @override
  String toString() => 'SvagaPlusAuthorizationException($statusCode)';
}

class SvagaPlusProtocolException implements Exception {
  final String message;
  const SvagaPlusProtocolException(this.message);

  @override
  String toString() => 'SvagaPlusProtocolException($message)';
}

class SvagaPlusHttpException implements Exception {
  final int statusCode;
  const SvagaPlusHttpException(this.statusCode);

  @override
  String toString() => 'SvagaPlusHttpException($statusCode)';
}

class SvagaPlusPairingStart {
  final String pairingId;
  final String userCode;
  final String pairingSecret;
  final DateTime expiresAt;
  final String? verificationUri;
  final int expiresIn;
  final int interval;

  const SvagaPlusPairingStart({
    required this.pairingId,
    required this.userCode,
    required this.pairingSecret,
    required this.expiresAt,
    this.verificationUri,
    this.expiresIn = 600,
    this.interval = 3,
  });
}

class SvagaPlusPairingPoll {
  final bool pending;
  final SvagaPlusCredentials? credentials;
  final int? initialCursor;
  final int interval;
  const SvagaPlusPairingPoll({
    required this.pending,
    this.credentials,
    this.initialCursor,
    this.interval = 3,
  });
}

class SvagaPlusTimerEventPage {
  final List<SvagaPlusSubscriptionEvent> events;
  final int nextCursor;
  final bool hasMore;
  final int highWatermark;

  const SvagaPlusTimerEventPage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
    required this.highWatermark,
  });
}

typedef TimerEventPage = SvagaPlusTimerEventPage;
typedef PairingStart = SvagaPlusPairingStart;
typedef PairingPoll = SvagaPlusPairingPoll;

class SvagaPlusApiClient {
  final http.Client client;
  final Uri baseUri;
  final bool allowInsecureTransport;
  static const requestTimeout = Duration(seconds: 15);

  SvagaPlusApiClient({
    http.Client? client,
    Uri? baseUri,
    bool? allowInsecureTransport,
  }) : client = client ?? http.Client(),
       baseUri = baseUri ?? AppConfig.svagaPlusUri,
       allowInsecureTransport = allowInsecureTransport ?? !kReleaseMode {
    if (!this.allowInsecureTransport && this.baseUri.scheme != 'https') {
      throw ArgumentError('SVAGA+ requires HTTPS in release configuration');
    }
  }

  Uri _endpoint(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return baseUri.replace(
      path: '${baseUri.path}$normalized',
      queryParameters: query,
    );
  }

  Future<SvagaPlusPairingStart> startPairing({
    String deviceName = 'Donaton Timer',
  }) async {
    final response = await _request(
      () => client.post(
        _endpoint('/api/timer/pairing/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'device_name': deviceName}),
      ),
    );
    final data = _data(response);
    return SvagaPlusPairingStart(
      pairingId: _requiredString(data, 'pairing_id'),
      userCode: _requiredString(data, 'user_code'),
      pairingSecret: _requiredString(data, 'pairing_secret'),
      expiresAt: _requiredDate(data, 'expires_at'),
      verificationUri: data['verification_uri'] as String?,
      expiresIn: (data['expires_in'] as num?)?.toInt() ?? 600,
      interval: (data['interval'] as num?)?.toInt() ?? 3,
    );
  }

  Future<SvagaPlusPairingPoll> pollPairing(
    String pairingId,
    String pairingSecret,
  ) async {
    final response = await _request(
      () => client.post(
        _endpoint('/api/timer/pairing/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'pairing_id': pairingId,
          'pairing_secret': pairingSecret,
        }),
      ),
      acceptStatus: {202},
    );
    final data = _data(response);
    if (response.statusCode == 202) {
      return SvagaPlusPairingPoll(
        pending: true,
        interval: (data['interval'] as num?)?.toInt() ?? 3,
      );
    }
    return SvagaPlusPairingPoll(
      pending: false,
      credentials: SvagaPlusCredentials(
        deviceId: _requiredString(data, 'device_id'),
        token: _requiredString(data, 'device_token'),
      ),
      initialCursor: (data['initial_cursor'] as num?)?.toInt() ?? 0,
      interval: (data['interval'] as num?)?.toInt() ?? 3,
    );
  }

  Future<void> completePairing(
    String pairingId,
    SvagaPlusCredentials credentials,
  ) async {
    await _request(
      () => client.post(
        _endpoint('/api/timer/pairing/complete'),
        headers: {
          'Content-Type': 'application/json',
          ..._deviceHeaders(credentials),
        },
        body: jsonEncode({'pairing_id': pairingId}),
      ),
    );
  }

  Future<SvagaPlusCredentials> consumePairing(
    String pairingId,
    String pairingSecret,
  ) async {
    final poll = await pollPairing(pairingId, pairingSecret);
    if (poll.pending || poll.credentials == null) {
      throw const SvagaPlusHttpException(202);
    }
    await completePairing(pairingId, poll.credentials!);
    return poll.credentials!;
  }

  Future<int> getHead(SvagaPlusCredentials credentials) async {
    final response = await _getWithRetry(
      _endpoint('/api/timer/head'),
      credentials,
    );
    final data = _data(response);
    return (data['high_watermark'] as num?)?.toInt() ??
        (data['head'] as num?)?.toInt() ??
        (data['cursor'] as num?)?.toInt() ??
        (throw const SvagaPlusProtocolException('Missing high_watermark'));
  }

  Future<SvagaPlusTimerEventPage> getEvents(
    SvagaPlusCredentials credentials, {
    required int after,
    required int until,
    int limit = 100,
  }) async {
    final response = await _getWithRetry(
      _endpoint('/api/timer/events', {
        'after': '$after',
        'until': '$until',
        'limit': '${limit.clamp(1, 100)}',
      }),
      credentials,
    );
    return _parsePage(_data(response));
  }

  Future<SvagaPlusTimerEventPage> getHistory(
    SvagaPlusCredentials credentials, {
    int? before,
    int limit = 50,
  }) async {
    final response = await _getWithRetry(
      _endpoint('/api/timer/history', {
        if (before != null) 'before': '$before',
        'limit': '${limit.clamp(1, 100)}',
      }),
      credentials,
    );
    return _parsePage(_data(response));
  }

  Future<void> ack(
    SvagaPlusCredentials credentials,
    String eventId,
    int cursor,
  ) async {
    await _request(
      () => client.post(
        _endpoint('/api/timer/ack'),
        headers: {
          'Content-Type': 'application/json',
          ..._deviceHeaders(credentials),
        },
        body: jsonEncode({'event_id': eventId, 'cursor': cursor}),
      ),
    );
  }

  Future<List<SvagaPlusSubscriptionEvent>> replay({
    required SvagaPlusCredentials credentials,
    required int after,
    int? until,
    int limit = 50,
  }) async {
    final page = await getEvents(
      credentials,
      after: after,
      until: until ?? (1 << 30),
      limit: limit,
    );
    return page.events;
  }

  Future<http.Response> _getWithRetry(
    Uri uri,
    SvagaPlusCredentials credentials,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _request(
          () => client.get(uri, headers: _deviceHeaders(credentials)),
        );
      } catch (error) {
        if (error is SvagaPlusAuthorizationException ||
            error is SvagaPlusProtocolException) {
          rethrow;
        }
        lastError = error;
        if (attempt < 2) {
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw lastError!;
  }

  Future<http.Response> _request(
    Future<http.Response> Function() request, {
    Set<int> acceptStatus = const {},
  }) async {
    final response = await request().timeout(requestTimeout);
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SvagaPlusAuthorizationException(response.statusCode);
    }
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        !acceptStatus.contains(response.statusCode)) {
      throw SvagaPlusHttpException(response.statusCode);
    }
    return response;
  }

  Map<String, dynamic> _data(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const SvagaPlusProtocolException('Response is not an object');
      }
      final map = Map<String, dynamic>.from(decoded);
      final data = map['data'];
      return data is Map ? Map<String, dynamic>.from(data) : map;
    } on SvagaPlusProtocolException {
      rethrow;
    } catch (_) {
      throw const SvagaPlusProtocolException('Malformed JSON response');
    }
  }

  SvagaPlusTimerEventPage _parsePage(Map<String, dynamic> data) {
    final rawEvents = data['events'];
    if (rawEvents is! List) {
      throw const SvagaPlusProtocolException('Missing events');
    }
    final events = rawEvents.map((item) {
      if (item is! Map) {
        throw const SvagaPlusProtocolException('Malformed event');
      }
      return SvagaPlusSubscriptionEvent.fromJson(
        Map<String, dynamic>.from(item),
      );
    }).toList()..sort((a, b) => a.cursor.compareTo(b.cursor));
    return SvagaPlusTimerEventPage(
      events: events,
      nextCursor:
          (data['next_cursor'] as num?)?.toInt() ??
          (events.isEmpty ? 0 : events.last.cursor),
      hasMore: data['has_more'] as bool? ?? false,
      highWatermark:
          (data['high_watermark'] as num?)?.toInt() ??
          (events.isEmpty ? 0 : events.last.cursor),
    );
  }

  Map<String, String> _deviceHeaders(SvagaPlusCredentials credentials) => {
    'Authorization': 'TimerDevice ${credentials.deviceId}:${credentials.token}',
  };

  String _requiredString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw SvagaPlusProtocolException('Missing $key');
    }
    return value;
  }

  DateTime _requiredDate(Map<String, dynamic> data, String key) {
    final value = _requiredString(data, key);
    final date = DateTime.tryParse(value);
    if (date == null) throw SvagaPlusProtocolException('Invalid $key');
    return date;
  }

  void dispose() => client.close();
}
