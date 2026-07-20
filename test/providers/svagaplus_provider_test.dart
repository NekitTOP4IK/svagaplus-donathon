import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
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
  Future<void> saveSvagaHistoryEntry(Map<String, dynamic> entry) async {
    final event = entry['event'];
    if (event is Map && event['id'] is String) {
      history[event['id'] as String] = entry;
    }
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
  int consumeCount = 0;
  List<SvagaPlusSubscriptionEvent> historyEvents = [];

  MemoryApi() : super(baseUri: Uri.parse('https://example.test'));

  @override
  Future<SvagaPlusPairingStart> startPairing({
    String deviceName = 'Donaton Timer',
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
      initialCursor: 4,
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
    expect(adapter.starts, 2);
    provider.dispose();
  });

  test('syncHistory imports only events after the device baseline', () async {
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

    await provider.init();
    await provider.syncHistory();

    expect(provider.history.map((item) => item.event.id), ['new']);
    provider.dispose();
  });

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
}
