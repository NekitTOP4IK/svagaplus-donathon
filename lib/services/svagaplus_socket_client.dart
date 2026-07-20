import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';
import 'svagaplus_api_client.dart';

abstract interface class SvagaPlusSocketTransport {
  Stream<Map<String, dynamic>> get ready;
  Stream<Map<String, dynamic>> get events;
  Stream<void> get revoked;
  Stream<void> get disconnected;
  void connect();
  void acknowledge(String eventId, int cursor);
  Future<void> dispose();
}

class SvagaPlusSocketClient implements SvagaPlusSocketTransport {
  final SvagaPlusCredentials credentials;
  final int lastCursor;
  final String appVersion;
  final Uri baseUri;
  io.Socket? _socket;
  bool _disposed = false;

  final _ready = StreamController<Map<String, dynamic>>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _revoked = StreamController<void>.broadcast();
  final _disconnected = StreamController<void>.broadcast();

  SvagaPlusSocketClient({
    required this.credentials,
    required this.lastCursor,
    required this.appVersion,
    Uri? baseUri,
  }) : baseUri = baseUri ?? AppConfig.svagaPlusUri;

  @override
  Stream<Map<String, dynamic>> get ready => _ready.stream;
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Stream<void> get revoked => _revoked.stream;
  @override
  Stream<void> get disconnected => _disconnected.stream;

  @override
  void connect() {
    if (_disposed) return;
    final socket = io.io(
      baseUri.replace(path: '${baseUri.path}/timer').toString(),
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({
            'device_id': credentials.deviceId,
            'token': credentials.token,
            'last_cursor': lastCursor,
            'app_version': appVersion,
          })
          .disableAutoConnect()
          .disableReconnection()
          .build(),
    );
    _socket = socket;
    socket.on('timer_ready', (data) {
      if (data is Map) _ready.add(Map<String, dynamic>.from(data));
    });
    socket.on('timer_event', (data) {
      if (data is Map) _events.add(Map<String, dynamic>.from(data));
    });
    socket.on('timer_revoked', (_) => _revoked.add(null));
    socket.on('revoked', (_) => _revoked.add(null));
    socket.on('connect_error', (_) => _disconnected.add(null));
    socket.on('disconnect', (_) => _disconnected.add(null));
    socket.connect();
  }

  @override
  void acknowledge(String eventId, int cursor) {
    _socket?.emit('timer_ack', {'event_id': eventId, 'cursor': cursor});
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _socket?.dispose();
    await _ready.close();
    await _events.close();
    await _revoked.close();
    await _disconnected.close();
  }
}
