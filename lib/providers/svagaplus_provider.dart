import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/svagaplus_history_entry.dart';
import '../models/svagaplus_pairing_session.dart';
import '../services/device_identity.dart';
import '../services/donation_service.dart';
import '../services/storage_service.dart';
import '../services/svagaplus_adapter.dart';
import '../services/svagaplus_api_client.dart';
import '../services/svagaplus_credential_store.dart';
import '../services/svagaplus_event_processor.dart';
import 'timer_provider.dart';

typedef SvagaPlusAdapterFactory =
    SvagaPlusAdapter Function(
      SvagaPlusApiClient api,
      SvagaPlusCredentials credentials,
      int cursor,
    );

class SvagaPlusProvider extends ChangeNotifier {
  static const appVersion = '3.0.6';
  final StorageService storage;
  final TimerProvider timerProvider;
  final DonationService donationService;
  final SvagaPlusApiClient api;
  final SvagaPlusCredentialStore credentialStore;
  SvagaPlusAdapter _adapter;
  final SvagaPlusAdapterFactory? adapterFactory;
  final Future<int?> Function(SvagaPlusCredentials credentials)? headLoader;
  final List<SvagaPlusHistoryEntry> _history;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _eventSubscription;
  SvagaPlusEventProcessor? _processor;
  SvagaPlusCredentials? _credentials;
  SvagaPlusSettings _settings;
  SvagaPlusStatus _status;
  int _baselineCursor = 0;
  bool _initialized = false;
  bool _historySyncing = false;
  Object? _historyError;
  SvagaPlusPairingSession _pairing = SvagaPlusPairingSession.idle;
  bool _cancelRequested = false;

  Future<bool> Function(Uri uri) openUrl = (_) async => false;

  SvagaPlusProvider({
    required this.storage,
    required this.timerProvider,
    required this.donationService,
    required this.api,
    required this.credentialStore,
    required SvagaPlusAdapter adapter,
    this.adapterFactory,
    this.headLoader,
    List<SvagaPlusHistoryEntry>? initialHistory,
  }) : _adapter = adapter,
       _history = List<SvagaPlusHistoryEntry>.from(initialHistory ?? const [])
         ..sort(_compareDesc),
       _settings = donationService.settings.svagaPlusSettings,
       _status = adapter.status;

  SvagaPlusSettings get settings => _settings;
  SvagaPlusStatus get status => _status;
  SvagaPlusAdapter get adapter => _adapter;
  SvagaPlusCredentials? get credentials => _credentials;
  bool get hasCredentials => _credentials != null;
  int get baselineCursor => _baselineCursor;

  /// Свежее сверху. Живой вид над внутренним списком — не копия: не
  /// сохраняйте результат в поле и не переносите через `await`, иначе
  /// последующие мутации истории будут видны через него.
  List<SvagaPlusHistoryEntry> get history =>
      UnmodifiableListView<SvagaPlusHistoryEntry>(_history);
  bool get historySyncing => _historySyncing;
  Object? get historyError => _historyError;
  SvagaPlusPairingSession get pairing => _pairing;
  bool get pairingInProgress => _pairing.inProgress;

  Future<void> init({bool autoConnect = true}) async {
    if (_initialized) return;
    _initialized = true;
    _credentials = await credentialStore.load();
    if (_history.isEmpty) {
      for (final raw in storage.loadSvagaHistory().values) {
        if (raw is Map) {
          try {
            _history.add(
              SvagaPlusHistoryEntry.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {}
        }
      }
    }
    _history.sort(_compareDesc);
    _baselineCursor = storage.loadSvagaCursor();
    final saved = donationService.settings;
    _settings = saved.svagaPlusSettings;
    final legacy = saved.getServiceConfig('SvagaPlus');
    if (legacy != null) {
      final values = legacy.credentials;
      _settings = _settings.copyWith(
        enabled: legacy.enabled,
        newSubscriptionSeconds:
            int.tryParse(values['newSubscriptionSeconds'] ?? '') ??
            _settings.newSubscriptionSeconds,
        renewedSubscriptionSeconds:
            int.tryParse(values['renewedSubscriptionSeconds'] ?? '') ??
            _settings.renewedSubscriptionSeconds,
      );
    }
    _listenToAdapter();
    if (autoConnect && _settings.enabled && _credentials != null) {
      _startAdapter();
    }
  }

  void _listenToAdapter() {
    _statusSubscription = _adapter.statuses.listen((value) {
      _status = value;
      notifyListeners();
      if (value == SvagaPlusStatus.authorizationRequired) {
        unawaited(_handleAuthorizationRequired());
      }
    });
    _processor = SvagaPlusEventProcessor(
      timerProvider: timerProvider,
      acknowledge: (event) async => _adapter.acknowledge(event),
    );
    _eventSubscription = _adapter.events.listen((event) async {
      try {
        final result = await _processor!.process(event, _settings);
        if (result.applied || result.duplicate) {
          final raw = storage.loadSvagaHistory()[event.id];
          if (raw is Map) {
            _history.removeWhere((item) => item.event.id == event.id);
            _insertSorted(
              SvagaPlusHistoryEntry.fromJson(Map<String, dynamic>.from(raw)),
            );
            notifyListeners();
          }
        }
      } catch (_) {}
    });
  }

  /// Порядок ленты и экрана истории: свежее сверху.
  /// Ключ — время события, курсор разрешает совпадения.
  static int _compareDesc(
    SvagaPlusHistoryEntry a,
    SvagaPlusHistoryEntry b,
  ) {
    final byTime = b.event.createdAt.compareTo(a.event.createdAt);
    return byTime != 0 ? byTime : b.event.cursor.compareTo(a.event.cursor);
  }

  /// Вставляет запись, сохраняя порядок, без полной пересортировки.
  void _insertSorted(SvagaPlusHistoryEntry entry) {
    var index = 0;
    while (index < _history.length &&
        _compareDesc(_history[index], entry) < 0) {
      index++;
    }
    _history.insert(index, entry);
  }

  void _startAdapter() => _adapter.start();

  Future<void> _replaceAdapter() async {
    if (_credentials == null || adapterFactory == null) return;
    await _adapter.stop();
    await _statusSubscription?.cancel();
    await _eventSubscription?.cancel();
    _adapter = adapterFactory!(api, _credentials!, storage.loadSvagaCursor());
    _status = _adapter.status;
    _listenToAdapter();
  }

  Future<void> _saveSettings() => donationService.updateSettings(
    donationService.settings.copyWith(svagaPlusSettings: _settings),
  );

  Future<void> enable() async {
    if (_credentials == null) return;
    final loadedHead = headLoader == null
        ? await api.getHead(_credentials!)
        : await headLoader!.call(_credentials!);
    final head = loadedHead ?? storage.loadSvagaCursor();
    await storage.replaceSvagaCursor(head);
    _baselineCursor = head;
    _settings = _settings.copyWith(enabled: true);
    await _saveSettings();
    _startAdapter();
    notifyListeners();
  }

  Future<void> updateSettings(SvagaPlusSettings settings) async {
    final wasEnabled = _settings.enabled;
    _settings = settings;
    await _saveSettings();
    if (!settings.enabled) {
      await _adapter.stop();
    } else if (!wasEnabled) {
      await enable();
    } else if (_credentials != null) {
      _startAdapter();
    }
    notifyListeners();
  }

  Future<void> connect() => enable();

  Future<void> syncHistory() async {
    if (_historySyncing) return;
    _historySyncing = true;
    _historyError = null;
    notifyListeners();
    try {
      _history.clear();
      for (final raw in storage.loadSvagaHistory().values) {
        if (raw is Map) {
          try {
            _history.add(
              SvagaPlusHistoryEntry.fromJson(Map<String, dynamic>.from(raw)),
            );
          } catch (_) {}
        }
      }
      _history.sort(_compareDesc);
    } catch (error) {
      _historyError = error;
    } finally {
      _historySyncing = false;
      notifyListeners();
    }
  }

  Future<void> startIfEnabled() async {
    if (_settings.enabled && _credentials != null) _startAdapter();
  }

  Future<void> disable() async {
    _settings = _settings.copyWith(enabled: false);
    await _saveSettings();
    await _adapter.stop();
    notifyListeners();
  }

  /// Сколько подряд сетевых неудач терпим, прежде чем сдаться.
  static const maxPairingNetworkRetries = 6;

  /// Шаг, которым нарезано ожидание, чтобы отмена откликалась быстро.
  static const pairingCancelSlice = Duration(milliseconds: 250);

  void _setPairing(SvagaPlusPairingSession value) {
    _pairing = value;
    notifyListeners();
  }

  /// Просит цикл остановиться. Отклик — в пределах [pairingCancelSlice].
  void cancelPairing() {
    if (!_pairing.inProgress) return;
    _cancelRequested = true;
  }

  Future<void> retryPairing({String? deviceName}) =>
      startPairing(deviceName: deviceName);

  /// Привязывает устройство. Не бросает: любая ошибка становится
  /// состоянием [SvagaPlusPairingState.failed] с типизированной причиной.
  Future<void> startPairing({String? deviceName}) async {
    if (_pairing.inProgress) return;
    _cancelRequested = false;
    _setPairing(
      const SvagaPlusPairingSession(state: SvagaPlusPairingState.starting),
    );

    final SvagaPlusPairingStart started;
    try {
      started = await api.startPairing(
        deviceName: deviceName ?? defaultDeviceName(),
        platform: currentPlatformName(),
        appVersion: appVersion,
      );
    } catch (error) {
      _setPairing(
        SvagaPlusPairingSession(
          state: SvagaPlusPairingState.failed,
          failure: _classifyPairingError(error),
        ),
      );
      return;
    }

    final uri =
        Uri.tryParse(started.verificationUri ?? '') ??
        Uri.parse('${api.baseUri}/timer/connect?code=${started.userCode}');

    bool opened;
    try {
      opened = await openUrl(uri);
    } catch (_) {
      opened = false;
    }

    _setPairing(
      SvagaPlusPairingSession(
        state: SvagaPlusPairingState.awaiting,
        userCode: started.userCode,
        verificationUri: uri,
        expiresAt: started.expiresAt,
        browserOpened: opened,
      ),
    );

    await _pollUntilPaired(started);
  }

  Future<void> _pollUntilPaired(SvagaPlusPairingStart started) async {
    var failures = 0;

    while (true) {
      if (_cancelRequested) {
        _setPairing(
          _pairing.copyWith(state: SvagaPlusPairingState.cancelled),
        );
        return;
      }
      if (!DateTime.now().toUtc().isBefore(started.expiresAt)) {
        _failPairing(SvagaPlusPairingFailure.expired);
        return;
      }

      final SvagaPlusPairingPoll poll;
      try {
        poll = await api.pollPairing(started.pairingId, started.pairingSecret);
      } catch (error) {
        final failure = _classifyPairingError(error);
        if (failure != SvagaPlusPairingFailure.network) {
          _failPairing(failure);
          return;
        }
        failures++;
        if (failures >= maxPairingNetworkRetries) {
          _failPairing(SvagaPlusPairingFailure.network);
          return;
        }
        await _sleepInSlices(
          Duration(seconds: (1 << (failures - 1)).clamp(1, 30)),
        );
        continue;
      }

      failures = 0;
      if (!poll.pending) {
        await _finishPairing(started, poll);
        return;
      }
      await _sleepInSlices(Duration(seconds: poll.interval.clamp(1, 30)));
    }
  }

  Future<void> _finishPairing(
    SvagaPlusPairingStart started,
    SvagaPlusPairingPoll poll,
  ) async {
    if (poll.credentials == null || poll.initialCursor == null) {
      _failPairing(SvagaPlusPairingFailure.unknown);
      return;
    }
    _setPairing(_pairing.copyWith(state: SvagaPlusPairingState.completing));

    try {
      await api.completePairing(started.pairingId, poll.credentials!);
    } catch (error) {
      _failPairing(_classifyPairingError(error));
      return;
    }

    final paired = poll.credentials!;
    await storage.replaceSvagaCursor(poll.initialCursor!);
    _baselineCursor = poll.initialCursor!;
    await credentialStore.save(paired);
    _credentials = paired;
    _settings = _settings.copyWith(enabled: true, deviceId: paired.deviceId);
    await _saveSettings();
    await _replaceAdapter();
    _startAdapter();
    _setPairing(
      const SvagaPlusPairingSession(state: SvagaPlusPairingState.done),
    );
  }

  void _failPairing(SvagaPlusPairingFailure failure) => _setPairing(
    _pairing.copyWith(state: SvagaPlusPairingState.failed, failure: failure),
  );

  /// Ожидание, нарезанное на отрезки, чтобы отмена не ждала весь интервал.
  Future<void> _sleepInSlices(Duration total) async {
    var remaining = total;
    while (remaining > Duration.zero && !_cancelRequested) {
      final slice = remaining < pairingCancelSlice
          ? remaining
          : pairingCancelSlice;
      await Future<void>.delayed(slice);
      remaining -= slice;
    }
  }

  SvagaPlusPairingFailure _classifyPairingError(Object error) {
    if (error is SvagaPlusAuthorizationException) {
      return SvagaPlusPairingFailure.unauthorized;
    }
    if (error is SvagaPlusHttpException) {
      final code = error.statusCode;
      if (code == 429) return SvagaPlusPairingFailure.rateLimited;
      if (code == 410) return SvagaPlusPairingFailure.expired;
      if (code == 400) return SvagaPlusPairingFailure.invalidSecret;
      if (code >= 500) return SvagaPlusPairingFailure.network;
      return SvagaPlusPairingFailure.unknown;
    }
    if (error is TimeoutException ||
        error is SocketException ||
        error is http.ClientException) {
      return SvagaPlusPairingFailure.network;
    }
    return SvagaPlusPairingFailure.unknown;
  }

  Future<void> _handleAuthorizationRequired() async {
    await _adapter.stop();
    await credentialStore.clear();
    _credentials = null;
    _settings = _settings.copyWith(enabled: false, clearDeviceId: true);
    await _saveSettings();
    notifyListeners();
  }

  Future<void> cancelHistoryEntry(String eventId) async {
    final result = await timerProvider.revertSvagaEvent(eventId);
    if (!result.changed) return;
    final index = _history.indexWhere((item) => item.event.id == eventId);
    if (index == -1) return;
    final old = _history[index];
    _history[index] = SvagaPlusHistoryEntry(
      event: old.event,
      appliedSeconds: old.appliedSeconds,
      status: SvagaPlusHistoryStatus.reverted,
      appliedAt: old.appliedAt,
      revertedAt: DateTime.now().toUtc(),
    );
    notifyListeners();
  }

  /// Очищает историю подписок — и в памяти, и в хранилище.
  /// Курсор сохраняется, см. [StorageService.clearSvagaHistory].
  Future<void> clearHistory() async {
    _history.clear();
    await storage.clearSvagaHistory();
    notifyListeners();
  }

  Future<void> restoreHistoryEntry(String eventId) async {
    final result = await timerProvider.restoreSvagaEvent(eventId);
    if (!result.changed) return;
    final index = _history.indexWhere((item) => item.event.id == eventId);
    if (index == -1) return;
    final old = _history[index];
    _history[index] = SvagaPlusHistoryEntry(
      event: old.event,
      appliedSeconds: old.appliedSeconds,
      status: SvagaPlusHistoryStatus.applied,
      appliedAt: old.appliedAt,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_statusSubscription?.cancel());
    unawaited(_eventSubscription?.cancel());
    unawaited(_adapter.dispose());
    super.dispose();
  }
}
