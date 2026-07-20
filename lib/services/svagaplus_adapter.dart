import 'dart:async';
import 'dart:math';

import '../models/svagaplus_subscription_event.dart';
import 'svagaplus_api_client.dart';
import 'svagaplus_socket_client.dart';

enum SvagaPlusStatus {
  disconnected,
  connecting,
  syncing,
  connected,
  reconnecting,
  error,
  authorizationRequired,
}

typedef SvagaPlusSocketFactory =
    SvagaPlusSocketTransport Function({
      required SvagaPlusCredentials credentials,
      required int lastCursor,
      required String appVersion,
    });

class SvagaPlusAdapter {
  final SvagaPlusApiClient api;
  final SvagaPlusCredentials credentials;
  final int lastCursor;
  final String appVersion;
  final SvagaPlusSocketFactory socketFactory;
  final FutureOr<int> Function()? cursorLoader;
  final Duration Function(int attempt) retryDelay;
  final Timer Function(Duration duration, void Function() callback)
  timerFactory;

  SvagaPlusSocketTransport? _socket;
  StreamSubscription? _readySubscription;
  StreamSubscription? _eventSubscription;
  StreamSubscription? _revokedSubscription;
  StreamSubscription? _disconnectedSubscription;
  Timer? _retryTimer;
  final _events = StreamController<SvagaPlusSubscriptionEvent>.broadcast();
  final _status = StreamController<SvagaPlusStatus>.broadcast();
  final List<SvagaPlusSubscriptionEvent> _liveBuffer = [];
  SvagaPlusStatus _currentStatus = SvagaPlusStatus.disconnected;
  int _reconnectAttempt = 0;
  bool _syncing = false;
  bool _waitingForReady = false;
  bool _running = false;
  late int _cursor = lastCursor;

  SvagaPlusAdapter({
    required this.api,
    required this.credentials,
    required this.lastCursor,
    required this.appVersion,
    SvagaPlusSocketFactory? socketFactory,
    this.cursorLoader,
    Duration Function(int attempt)? retryDelay,
    Timer Function(Duration duration, void Function() callback)? timerFactory,
  }) : socketFactory =
           socketFactory ??
           (({
             required credentials,
             required lastCursor,
             required appVersion,
           }) => SvagaPlusSocketClient(
             credentials: credentials,
             lastCursor: lastCursor,
             appVersion: appVersion,
           )),
       retryDelay = retryDelay ?? _defaultRetryDelay,
       timerFactory =
           timerFactory ?? ((duration, callback) => Timer(duration, callback));

  Stream<SvagaPlusSubscriptionEvent> get events => _events.stream;
  Stream<SvagaPlusStatus> get statuses => _status.stream;
  SvagaPlusStatus get status => _currentStatus;

  static Duration _defaultRetryDelay(int attempt) {
    final seconds = min(30, 1 << min(attempt - 1, 5));
    return Duration(seconds: seconds);
  }

  void _setStatus(SvagaPlusStatus value) {
    _currentStatus = value;
    if (!_status.isClosed) _status.add(value);
  }

  void start() {
    if (_running) return;
    _running = true;
    _reconnectAttempt = 0;
    _waitingForReady = true;
    unawaited(_connect(isReconnect: false));
  }

  Future<void> _connect({required bool isReconnect}) async {
    if (!_running) return;
    if (isReconnect && cursorLoader != null) {
      _cursor = await cursorLoader!();
      if (!_running) return;
    }
    _waitingForReady = true;
    _setStatus(
      isReconnect ? SvagaPlusStatus.reconnecting : SvagaPlusStatus.connecting,
    );
    final socket = socketFactory(
      credentials: credentials,
      lastCursor: _cursor,
      appVersion: appVersion,
    );
    _socket = socket;
    _eventSubscription = socket.events.listen(_receiveLive);
    _readySubscription = socket.ready.listen(_syncFromReady);
    _revokedSubscription = socket.revoked.listen((_) {
      _running = false;
      _retryTimer?.cancel();
      _setStatus(SvagaPlusStatus.authorizationRequired);
    });
    _disconnectedSubscription = socket.disconnected.listen((_) {
      if (_running) _scheduleReconnect();
    });
    socket.connect();
  }

  int get _currentCursor => _cursor;

  void _receiveLive(Map<String, dynamic> json) {
    try {
      final event = SvagaPlusSubscriptionEvent.fromJson(json);
      if (_waitingForReady || _syncing) {
        _liveBuffer.add(event);
      } else if (event.cursor > _currentCursor) {
        _events.add(event);
      }
    } catch (_) {
      _setStatus(SvagaPlusStatus.error);
    }
  }

  Future<void> _syncFromReady(Map<String, dynamic> ready) async {
    if (!_running || _syncing) return;
    _waitingForReady = false;
    _syncing = true;
    _setStatus(SvagaPlusStatus.syncing);
    final high = (ready['high_watermark'] as num?)?.toInt() ?? _currentCursor;
    final startCursor = _currentCursor;
    try {
      final replayed = <SvagaPlusSubscriptionEvent>[];
      var cursor = startCursor;
      while (cursor < high) {
        final page = await api.replay(
          credentials: credentials,
          after: cursor,
          until: high,
        );
        final unseen = page.where((event) => event.cursor > cursor).toList()
          ..sort((a, b) => a.cursor.compareTo(b.cursor));
        if (unseen.isEmpty) break;
        replayed.addAll(unseen);
        cursor = unseen.last.cursor;
      }
      final merged = <String, SvagaPlusSubscriptionEvent>{};
      for (final event in [...replayed, ..._liveBuffer]) {
        if (event.cursor > startCursor) merged[event.id] = event;
      }
      _liveBuffer.clear();
      final ordered = merged.values.toList()
        ..sort((a, b) {
          final cursorOrder = a.cursor.compareTo(b.cursor);
          return cursorOrder == 0 ? a.id.compareTo(b.id) : cursorOrder;
        });
      for (final event in ordered) {
        if (_running) _events.add(event);
      }
      _syncing = false;
      _reconnectAttempt = 0;
      _setStatus(SvagaPlusStatus.connected);
    } on SvagaPlusAuthorizationException {
      _syncing = false;
      _running = false;
      _setStatus(SvagaPlusStatus.authorizationRequired);
    } catch (_) {
      _syncing = false;
      _setStatus(SvagaPlusStatus.error);
      if (_running) _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (!_running || _retryTimer != null) return;
    if (_readySubscription != null) {
      unawaited(_readySubscription!.cancel());
    }
    if (_eventSubscription != null) {
      unawaited(_eventSubscription!.cancel());
    }
    if (_revokedSubscription != null) {
      unawaited(_revokedSubscription!.cancel());
    }
    if (_disconnectedSubscription != null) {
      unawaited(_disconnectedSubscription!.cancel());
    }
    if (_socket != null) unawaited(_socket!.dispose());
    _socket = null;
    _syncing = false;
    _waitingForReady = true;
    _reconnectAttempt++;
    _setStatus(SvagaPlusStatus.reconnecting);
    _retryTimer = timerFactory(retryDelay(_reconnectAttempt), () {
      _retryTimer = null;
      unawaited(_connect(isReconnect: true));
    });
  }

  void acknowledge(SvagaPlusSubscriptionEvent event) =>
      _socket?.acknowledge(event.id, event.cursor);

  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _readySubscription?.cancel();
    await _eventSubscription?.cancel();
    await _revokedSubscription?.cancel();
    await _disconnectedSubscription?.cancel();
    _readySubscription = null;
    _eventSubscription = null;
    _revokedSubscription = null;
    _disconnectedSubscription = null;
    await _socket?.dispose();
    _socket = null;
    _liveBuffer.clear();
    _syncing = false;
    _setStatus(SvagaPlusStatus.disconnected);
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
    await _status.close();
  }
}
