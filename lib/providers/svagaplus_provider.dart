import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/svagaplus_history_entry.dart';
import '../models/svagaplus_subscription_event.dart';
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
       _history = List<SvagaPlusHistoryEntry>.from(initialHistory ?? const []),
       _settings = donationService.settings.svagaPlusSettings,
       _status = adapter.status;

  SvagaPlusSettings get settings => _settings;
  SvagaPlusStatus get status => _status;
  SvagaPlusAdapter get adapter => _adapter;
  SvagaPlusCredentials? get credentials => _credentials;
  bool get hasCredentials => _credentials != null;
  int get baselineCursor => _baselineCursor;
  List<SvagaPlusHistoryEntry> get history =>
      List<SvagaPlusHistoryEntry>.unmodifiable(
        _history..sort((a, b) => b.event.cursor.compareTo(a.event.cursor)),
      );
  bool get historySyncing => _historySyncing;
  Object? get historyError => _historyError;

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
            _history.add(
              SvagaPlusHistoryEntry.fromJson(Map<String, dynamic>.from(raw)),
            );
            notifyListeners();
          }
        }
      } catch (_) {}
    });
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
    await storage.setSvagaCursor(head);
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

  Future<void> connect() async {
    if (_credentials == null) return;
    _settings = _settings.copyWith(enabled: true);
    await _saveSettings();
    _startAdapter();
    notifyListeners();
  }

  Future<void> syncHistory() async {
    if (_credentials == null || !_settings.enabled || _historySyncing) return;
    _historySyncing = true;
    _historyError = null;
    notifyListeners();
    try {
      final known = <String>{for (final item in _history) item.event.id};
      final baseline = _baselineCursor;
      int? before;
      while (true) {
        final page = await api.getHistory(_credentials!, before: before);
        if (page.events.isEmpty) break;
        for (final event in page.events) {
          if (event.cursor <= baseline || known.contains(event.id)) continue;
          final seconds = event.eventType == SvagaPlusEventType.newSubscription
              ? _settings.newSubscriptionSeconds
              : _settings.renewedSubscriptionSeconds;
          final entry = SvagaPlusHistoryEntry(
            event: event,
            appliedSeconds: seconds,
            status: SvagaPlusHistoryStatus.applied,
            appliedAt: event.createdAt,
          );
          await storage.saveSvagaHistoryEntry(entry.toJson());
          _history.add(entry);
          known.add(event.id);
        }
        if (!page.hasMore) break;
        final nextBefore = page.events.first.cursor;
        if (nextBefore <= baseline || nextBefore == before) break;
        before = nextBefore;
      }
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

  Future<void> startPairing({String deviceName = 'Donaton Timer'}) async {
    final pairing = await api.startPairing(deviceName: deviceName);
    final uri =
        Uri.tryParse(pairing.verificationUri ?? '') ??
        Uri.parse('${api.baseUri}/timer/connect?code=${pairing.userCode}');
    final opened = await openUrl(uri);
    if (!opened) {
      throw StateError('Не удалось открыть ссылку сопряжения в браузере');
    }
    SvagaPlusPairingPoll poll = const SvagaPlusPairingPoll(pending: true);
    while (poll.pending && DateTime.now().toUtc().isBefore(pairing.expiresAt)) {
      poll = await api.pollPairing(pairing.pairingId, pairing.pairingSecret);
      if (poll.pending) {
        await Future<void>.delayed(
          Duration(seconds: poll.interval.clamp(1, 30)),
        );
      }
    }
    if (poll.pending || poll.credentials == null) {
      throw const SvagaPlusHttpException(410);
    }
    await api.completePairing(pairing.pairingId, poll.credentials!);
    final paired = poll.credentials!;
    await credentialStore.save(paired);
    _credentials = paired;
    _settings = _settings.copyWith(enabled: false, deviceId: paired.deviceId);
    await _saveSettings();
    await _replaceAdapter();
    notifyListeners();
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
