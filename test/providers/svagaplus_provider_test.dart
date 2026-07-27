import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/models/svagaplus_history_entry.dart';
import 'package:donaton_timer/models/svagaplus_pairing_session.dart';
import 'package:donaton_timer/models/app_settings.dart';
import 'package:donaton_timer/models/service_config.dart';
import 'package:donaton_timer/models/svagaplus_settings.dart';
import 'package:donaton_timer/providers/svagaplus_provider.dart';
import 'package:donaton_timer/providers/timer_provider.dart';
import 'package:donaton_timer/services/donation_service.dart';
import 'package:donaton_timer/services/svagaplus_adapter.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';
import 'package:donaton_timer/services/svagaplus_credential_store.dart';
import 'package:donaton_timer/services/storage_service.dart';

class MemoryStorage extends StorageService {
  int cursor = 4;
  final Map<String, dynamic> history = {};

  @override
  int loadSvagaCursor() => cursor;

  @override
  Map<String, dynamic> loadSvagaHistory() => Map<String, dynamic>.from(history);

  @override
  Future<void> setSvagaCursor(int value) async {
    if (value > cursor) cursor = value;
  }

  @override
  Future<void> replaceSvagaCursor(int value) async {
    cursor = value < 0 ? 0 : value;
  }

  @override
  Future<void> saveSvagaHistoryEntry(Map<String, dynamic> entry) async {
    final event = entry['event'];
    if (event is Map && event['id'] is String) {
      history[event['id'] as String] = entry;
    }
  }

  @override
  Future<void> clearSvagaHistory() async {
    history.clear();
    // Cursor is intentionally left untouched, mirroring the real
    // StorageService.clearSvagaHistory contract.
  }

  // Mirrors StorageService.applySvagaEvent's in-memory semantics without
  // touching disk (the real implementation goes through path_provider,
  // which throws MissingPluginException under flutter test).
  @override
  Future<SvagaPlusMutationResult> applySvagaEvent({
    required SvagaPlusSubscriptionEvent event,
    required int seconds,
    required int currentDuration,
  }) async {
    final existing = history[event.id];
    if (existing is Map) {
      return SvagaPlusMutationResult(
        changed: false,
        duration: currentDuration,
        appliedSeconds: (existing['appliedSeconds'] as num?)?.toInt() ?? 0,
        status: existing['status'] as String? ?? 'applied',
      );
    }
    history[event.id] = {
      'event': event.toJson(),
      'appliedSeconds': seconds,
      'status': 'applied',
      'appliedAt': DateTime.now().toUtc().toIso8601String(),
      'revertedAt': null,
    };
    if (event.cursor > cursor) cursor = event.cursor;
    return SvagaPlusMutationResult(
      changed: true,
      duration: currentDuration + seconds,
      appliedSeconds: seconds,
      status: 'applied',
    );
  }
}

class MemoryDonationService extends DonationService {
  AppSettings current = const AppSettings();

  MemoryDonationService(super.storage);

  @override
  AppSettings get settings => current;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    current = settings;
  }
}

class MemoryCredentials extends SvagaPlusCredentialStore {
  SvagaPlusCredentials? value;
  bool cleared = false;

  MemoryCredentials([this.value]);

  @override
  Future<SvagaPlusCredentials?> load() async => value;

  @override
  Future<void> save(SvagaPlusCredentials credentials) async {
    value = credentials;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    value = null;
  }
}

class MemoryApi extends SvagaPlusApiClient {
  int head = 0;
  SvagaPlusCredentials? pairedCredentials;
  int? pairingInitialCursor = 4;
  int consumeCount = 0;
  int getHistoryCalls = 0;
  List<SvagaPlusSubscriptionEvent> historyEvents = [];

  MemoryApi() : super(baseUri: Uri.parse('https://example.test'));

  @override
  Future<SvagaPlusPairingStart> startPairing({
    String deviceName = 'Donaton Timer',
    String? platform,
    String? appVersion,
  }) async {
    return SvagaPlusPairingStart(
      pairingId: 'pairing-id',
      userCode: '1234-5678',
      pairingSecret: 'pairing-secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(seconds: 30)),
    );
  }

  @override
  Future<SvagaPlusPairingPoll> pollPairing(
    String pairingId,
    String pairingSecret,
  ) async {
    return SvagaPlusPairingPoll(
      pending: false,
      credentials: pairedCredentials ??= const SvagaPlusCredentials(
        deviceId: 'device-1',
        token: 'secret-token',
      ),
      initialCursor: pairingInitialCursor,
    );
  }

  @override
  Future<void> completePairing(
    String pairingId,
    SvagaPlusCredentials credentials,
  ) async {}

  @override
  Future<SvagaPlusTimerEventPage> getHistory(
    SvagaPlusCredentials credentials, {
    int? before,
    int limit = 50,
  }) async {
    getHistoryCalls++;
    final events = historyEvents
        .where((event) => before == null || event.cursor < before)
        .toList();
    return SvagaPlusTimerEventPage(
      events: events,
      nextCursor: events.isEmpty ? 0 : events.first.cursor,
      hasMore: false,
      highWatermark: events.isEmpty ? 0 : events.last.cursor,
    );
  }
}

class MemoryAdapter extends SvagaPlusAdapter {
  final StreamController<SvagaPlusSubscriptionEvent> eventController =
      StreamController<SvagaPlusSubscriptionEvent>.broadcast();
  final StreamController<SvagaPlusStatus> statusController =
      StreamController<SvagaPlusStatus>.broadcast();
  SvagaPlusStatus currentStatus = SvagaPlusStatus.disconnected;
  int starts = 0;
  int stops = 0;

  MemoryAdapter(
    SvagaPlusApiClient api,
    SvagaPlusCredentials credentials,
    int cursor,
  ) : super(
        api: api,
        credentials: credentials,
        lastCursor: cursor,
        appVersion: 'test',
      );

  @override
  Stream<SvagaPlusSubscriptionEvent> get events => eventController.stream;

  @override
  Stream<SvagaPlusStatus> get statuses => statusController.stream;

  @override
  SvagaPlusStatus get status => currentStatus;

  @override
  void start() {
    starts++;
    currentStatus = SvagaPlusStatus.connected;
    statusController.add(currentStatus);
  }

  @override
  Future<void> stop() async {
    stops++;
    currentStatus = SvagaPlusStatus.disconnected;
    statusController.add(currentStatus);
  }

  @override
  Future<void> dispose() async {
    await eventController.close();
    await statusController.close();
  }
}

MemoryAdapter adapterFor(
  SvagaPlusApiClient api,
  SvagaPlusCredentials credentials,
  int cursor,
) => MemoryAdapter(api, credentials, cursor);

SvagaPlusProvider makeProvider({
  required MemoryStorage storage,
  required MemoryDonationService donationService,
  required MemoryApi api,
  required MemoryCredentials credentials,
  required MemoryAdapter adapter,
  int? Function()? headLoader,
}) {
  return SvagaPlusProvider(
    storage: storage,
    timerProvider: TimerProvider(storage),
    donationService: donationService,
    api: api,
    credentialStore: credentials,
    adapter: adapter,
    adapterFactory: adapterFor,
    headLoader: headLoader == null ? null : (_) async => headLoader(),
  );
}

void main() {
  test(
    'defaults to disabled and does not connect without credentials',
    () async {
      final storage = MemoryStorage();
      final donationService = MemoryDonationService(storage);
      final credentials = MemoryCredentials();
      final adapter = MemoryAdapter(
        MemoryApi(),
        const SvagaPlusCredentials(deviceId: 'unused', token: 'unused'),
        storage.cursor,
      );
      final provider = makeProvider(
        storage: storage,
        donationService: donationService,
        api: MemoryApi(),
        credentials: credentials,
        adapter: adapter,
      );

      await provider.init();

      expect(provider.settings.enabled, isFalse);
      expect(provider.status, SvagaPlusStatus.disconnected);
      expect(adapter.starts, 0);
      provider.dispose();
    },
  );

  test(
    'startup auto-connects only when saved settings are enabled and credentials exist',
    () async {
      final storage = MemoryStorage();
      final donationService = MemoryDonationService(storage);
      final credentials = MemoryCredentials(
        const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
      );
      final api = MemoryApi();
      final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
      donationService.current = const AppSettings().updateServiceConfig(
        const ServiceConfig(
          serviceName: 'SvagaPlus',
          enabled: true,
          credentials: {
            'newSubscriptionSeconds': '900',
            'renewedSubscriptionSeconds': '900',
          },
        ),
      );
      final provider = makeProvider(
        storage: storage,
        donationService: donationService,
        api: api,
        credentials: credentials,
        adapter: adapter,
      );

      await provider.init();

      expect(adapter.starts, 1);
      provider.dispose();
    },
  );

  test(
    'first enable saves the current server head before connecting',
    () async {
      final storage = MemoryStorage();
      final donationService = MemoryDonationService(storage);
      final credentials = MemoryCredentials(
        const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
      );
      final api = MemoryApi()..head = 90;
      final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
      final provider = makeProvider(
        storage: storage,
        donationService: donationService,
        api: api,
        credentials: credentials,
        adapter: adapter,
        headLoader: () => api.head,
      );

      await provider.init();
      await provider.enable();

      expect(provider.settings.enabled, isTrue);
      expect(storage.cursor, 90);
      expect(provider.baselineCursor, 90);
      expect(adapter.starts, 1);
      provider.dispose();
    },
  );

  test('re-enabling after disable saves a new server head', () async {
    final storage = MemoryStorage();
    final donationService = MemoryDonationService(storage);
    final credentials = MemoryCredentials(
      const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
    );
    final api = MemoryApi()..head = 20;
    final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
    final provider = makeProvider(
      storage: storage,
      donationService: donationService,
      api: api,
      credentials: credentials,
      adapter: adapter,
      headLoader: () => api.head,
    );

    await provider.init();
    await provider.enable();
    await provider.disable();
    api.head = 31;
    await provider.enable();

    expect(provider.baselineCursor, 31);
    expect(storage.cursor, 31);
    expect(adapter.starts, 2);
    provider.dispose();
  });

  test('syncHistory reloads only the local ledger', () async {
    final storage = MemoryStorage()..cursor = 4;
    final donationService = MemoryDonationService(storage);
    donationService.current = const AppSettings().copyWith(
      svagaPlusSettings: const SvagaPlusSettings(enabled: true),
    );
    final credentials = MemoryCredentials(
      const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
    );
    final api = MemoryApi()
      ..historyEvents = [
        SvagaPlusSubscriptionEvent(
          id: 'old',
          cursor: 3,
          eventType: 'new_subscription',
          subscriberName: 'Old',
          createdAt: DateTime.utc(2026, 7, 20),
        ),
        SvagaPlusSubscriptionEvent(
          id: 'new',
          cursor: 5,
          eventType: 'renewed_subscription',
          subscriberName: 'New',
          createdAt: DateTime.utc(2026, 7, 20),
        ),
      ];
    final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
    final provider = makeProvider(
      storage: storage,
      donationService: donationService,
      api: api,
      credentials: credentials,
      adapter: adapter,
    );

    final local = SvagaPlusHistoryEntry(
      event: SvagaPlusSubscriptionEvent(
        id: 'local',
        cursor: 2,
        eventType: 'new_subscription',
        subscriberName: 'Local',
        createdAt: DateTime.utc(2026, 7, 20),
      ),
      appliedSeconds: 900,
      status: SvagaPlusHistoryStatus.applied,
      appliedAt: DateTime.utc(2026, 7, 20),
    );
    final reverted = SvagaPlusHistoryEntry(
      event: SvagaPlusSubscriptionEvent(
        id: 'reverted',
        cursor: 1,
        eventType: 'renewed_subscription',
        subscriberName: 'Reverted',
        createdAt: DateTime.utc(2026, 7, 19),
      ),
      appliedSeconds: 900,
      status: SvagaPlusHistoryStatus.reverted,
      appliedAt: DateTime.utc(2026, 7, 19),
      revertedAt: DateTime.utc(2026, 7, 20),
    );
    storage.history[local.event.id] = local.toJson();
    storage.history[reverted.event.id] = reverted.toJson();

    await provider.init();
    await provider.syncHistory();

    expect(provider.history.map((item) => item.event.id), [
      'local',
      'reverted',
    ]);
    expect(provider.history.map((item) => item.status), [
      SvagaPlusHistoryStatus.applied,
      SvagaPlusHistoryStatus.reverted,
    ]);
    expect(storage.history.containsKey('new'), isFalse);
    expect(api.getHistoryCalls, 0);
    provider.dispose();
  });

  test(
    'clearHistory empties provider.history and storage, and notifies listeners',
    () async {
      final storage = MemoryStorage()..cursor = 12;
      final entry = SvagaPlusHistoryEntry(
        event: SvagaPlusSubscriptionEvent(
          id: 'kept-until-cleared',
          cursor: 12,
          eventType: 'new_subscription',
          subscriberName: 'Alice',
          createdAt: DateTime.utc(2026, 7, 20),
        ),
        appliedSeconds: 900,
        status: SvagaPlusHistoryStatus.applied,
        appliedAt: DateTime.utc(2026, 7, 20),
      );
      storage.history[entry.event.id] = entry.toJson();
      final donationService = MemoryDonationService(storage);
      final credentials = MemoryCredentials();
      final api = MemoryApi();
      final adapter = MemoryAdapter(
        api,
        const SvagaPlusCredentials(deviceId: 'unused', token: 'unused'),
        storage.cursor,
      );
      final provider = makeProvider(
        storage: storage,
        donationService: donationService,
        api: api,
        credentials: credentials,
        adapter: adapter,
      );

      await provider.init(autoConnect: false);
      expect(provider.history, isNotEmpty);

      var notified = false;
      provider.addListener(() => notified = true);

      await provider.clearHistory();

      expect(provider.history, isEmpty);
      expect(storage.history, isEmpty);
      expect(notified, isTrue);
      // The cursor is not this method's job — StorageService.clearSvagaHistory
      // owns that guarantee — but a regression that routed clearHistory
      // through a wipe-everything call would show up here too.
      expect(storage.cursor, 12);
      provider.dispose();
    },
  );

  test('pairing stores credentials before completing the connection', () async {
    final storage = MemoryStorage();
    final donationService = MemoryDonationService(storage);
    final credentials = MemoryCredentials();
    final api = MemoryApi();
    final adapter = MemoryAdapter(
      api,
      const SvagaPlusCredentials(deviceId: 'unused', token: 'unused'),
      storage.cursor,
    );
    final opened = <Uri>[];
    final provider =
        makeProvider(
            storage: storage,
            donationService: donationService,
            api: api,
            credentials: credentials,
            adapter: adapter,
          )
          ..openUrl = (uri) async {
            opened.add(uri);
            return true;
          };

    await provider.init();
    await provider.startPairing();

    expect(opened, isNotEmpty);
    expect(credentials.value?.deviceId, 'device-1');
    expect(provider.hasCredentials, isTrue);
    expect(storage.cursor, 4);
    expect(provider.baselineCursor, 4);
    expect(adapter.starts, 0);
    provider.dispose();
  });

  test('pairing refuses credentials without an initial cursor', () async {
    final storage = MemoryStorage();
    final donationService = MemoryDonationService(storage);
    final credentials = MemoryCredentials();
    final api = MemoryApi()..pairingInitialCursor = null;
    final adapter = MemoryAdapter(
      api,
      const SvagaPlusCredentials(deviceId: 'unused', token: 'unused'),
      storage.cursor,
    );
    final provider = makeProvider(
      storage: storage,
      donationService: donationService,
      api: api,
      credentials: credentials,
      adapter: adapter,
    )..openUrl = (_) async => true;

    await provider.init();

    // startPairing никогда не бросает (Task 6) — отсутствие initial_cursor
    // становится типизированным провалом состояния, а не исключением.
    await provider.startPairing();

    expect(provider.pairing.state, SvagaPlusPairingState.failed);
    expect(provider.pairing.failure, SvagaPlusPairingFailure.unknown);
    expect(credentials.value, isNull);
    expect(adapter.starts, 0);
    provider.dispose();
  });

  test('revocation clears credentials and disables integration', () async {
    final storage = MemoryStorage();
    final donationService = MemoryDonationService(storage);
    final credentials = MemoryCredentials(
      const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
    );
    final api = MemoryApi();
    final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
    donationService.current = const AppSettings().updateServiceConfig(
      const ServiceConfig(
        serviceName: 'SvagaPlus',
        enabled: true,
        credentials: {
          'newSubscriptionSeconds': '900',
          'renewedSubscriptionSeconds': '900',
        },
      ),
    );
    final provider = makeProvider(
      storage: storage,
      donationService: donationService,
      api: api,
      credentials: credentials,
      adapter: adapter,
    );

    await provider.init();
    adapter.currentStatus = SvagaPlusStatus.authorizationRequired;
    adapter.statusController.add(SvagaPlusStatus.authorizationRequired);
    await Future<void>.delayed(Duration.zero);

    expect(credentials.cleared, isTrue);
    expect(provider.settings.enabled, isFalse);
    provider.dispose();
  });

  group('_listenToAdapter live event insertion', () {
    // The event handler processes events through a chain of futures
    // (processor -> timerProvider -> storage mutation queue), so a single
    // microtask turn is not enough to observe the resulting history update.
    Future<void> flushMicrotasks() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    SvagaPlusSubscriptionEvent liveEvent(String id, int hour, int cursor) =>
        SvagaPlusSubscriptionEvent(
          id: id,
          cursor: cursor,
          eventType: 'new_subscription',
          subscriberName: id,
          createdAt: DateTime.utc(2026, 7, 20, hour),
        );

    Map<String, dynamic> seededHistory(String id, int hour, int cursor) {
      final event = liveEvent(id, hour, cursor);
      return SvagaPlusHistoryEntry(
        event: event,
        appliedSeconds: 900,
        status: SvagaPlusHistoryStatus.applied,
        appliedAt: event.createdAt,
      ).toJson();
    }

    test(
      'event older than the newest existing entry lands in the middle',
      () async {
        final storage = MemoryStorage()
          ..history.addAll({
            'a': seededHistory('a', 20, 1),
            'c': seededHistory('c', 10, 1),
          });
        final donationService = MemoryDonationService(storage)
          ..current = const AppSettings().copyWith(
            svagaPlusSettings: const SvagaPlusSettings(enabled: true),
          );
        final credentials = MemoryCredentials(
          const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
        );
        final api = MemoryApi();
        final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
        final provider = makeProvider(
          storage: storage,
          donationService: donationService,
          api: api,
          credentials: credentials,
          adapter: adapter,
        );

        await provider.init(autoConnect: false);
        // Older than 'a' (hour 20) but newer than 'c' (hour 10).
        adapter.eventController.add(liveEvent('b', 15, 2));
        await flushMicrotasks();

        expect(provider.history.map((e) => e.event.id).toList(), [
          'a',
          'b',
          'c',
        ]);
        provider.dispose();
      },
    );

    test(
      'event colliding on createdAt is ordered by cursor, higher first',
      () async {
        final storage = MemoryStorage()
          ..history.addAll({'x': seededHistory('x', 15, 3)});
        final donationService = MemoryDonationService(storage)
          ..current = const AppSettings().copyWith(
            svagaPlusSettings: const SvagaPlusSettings(enabled: true),
          );
        final credentials = MemoryCredentials(
          const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
        );
        final api = MemoryApi();
        final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
        final provider = makeProvider(
          storage: storage,
          donationService: donationService,
          api: api,
          credentials: credentials,
          adapter: adapter,
        );

        await provider.init(autoConnect: false);
        // Same createdAt (hour 15) as 'x', but a higher cursor (7 > 3).
        adapter.eventController.add(liveEvent('y', 15, 7));
        await flushMicrotasks();

        expect(provider.history.map((e) => e.event.id).toList(), ['y', 'x']);
        provider.dispose();
      },
    );

    test('newest event lands at index 0', () async {
      final storage = MemoryStorage()
        ..history.addAll({
          'old': seededHistory('old', 10, 1),
          'mid': seededHistory('mid', 15, 1),
        });
      final donationService = MemoryDonationService(storage)
        ..current = const AppSettings().copyWith(
          svagaPlusSettings: const SvagaPlusSettings(enabled: true),
        );
      final credentials = MemoryCredentials(
        const SvagaPlusCredentials(deviceId: 'device-1', token: 'token'),
      );
      final api = MemoryApi();
      final adapter = MemoryAdapter(api, credentials.value!, storage.cursor);
      final provider = makeProvider(
        storage: storage,
        donationService: donationService,
        api: api,
        credentials: credentials,
        adapter: adapter,
      );

      await provider.init(autoConnect: false);
      adapter.eventController.add(liveEvent('new', 25, 5));
      await flushMicrotasks();

      expect(provider.history.map((e) => e.event.id).toList(), [
        'new',
        'mid',
        'old',
      ]);
      provider.dispose();
    });
  });
}
