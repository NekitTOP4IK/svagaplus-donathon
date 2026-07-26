import 'package:flutter_test/flutter_test.dart';

import 'package:donaton_timer/models/app_settings.dart';
import 'package:donaton_timer/models/svagaplus_pairing_session.dart';
import 'package:donaton_timer/providers/svagaplus_provider.dart';
import 'package:donaton_timer/providers/timer_provider.dart';
import 'package:donaton_timer/services/donation_service.dart';
import 'package:donaton_timer/services/storage_service.dart';
import 'package:donaton_timer/services/svagaplus_adapter.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';
import 'package:donaton_timer/services/svagaplus_credential_store.dart';

class PairStorage extends StorageService {
  int cursor = 0;

  @override
  Map<String, dynamic> loadSvagaHistory() => {};

  @override
  int loadSvagaCursor() => cursor;

  @override
  Future<void> replaceSvagaCursor(int value) async => cursor = value;
}

/// `DonationService`, полностью в памяти. Реальный `DonationService` на
/// `updateSettings` пишет на диск через `StorageService.saveSettings` (под
/// `flutter test` там нет `ServicesBinding.instance` для `path_provider` —
/// падает с "Binding has not yet been initialized") и попутно бьёт по сети
/// через `CurrencyConverterService().fetchRates(...)`, если курсы ещё не
/// загружены. Тот же приём, что и `MemoryDonationService` в
/// `svagaplus_provider_test.dart`.
class PairDonationService extends DonationService {
  AppSettings current = const AppSettings();

  PairDonationService(super.storage);

  @override
  AppSettings get settings => current;

  @override
  Future<void> updateSettings(AppSettings settings) async {
    current = settings;
  }
}

/// Все три метода переопределены, поэтому платформенный канал не задействуется.
/// Если понадобится не переопределять их — инжектите фейк секретов через сеем
/// `SvagaPlusCredentialStore(storage: ...)`, как в
/// `test/services/svagaplus_secure_storage_test.dart`: живой конструктор по
/// умолчанию заводит `FlutterSecureStorage`, и под `flutter test` вызов
/// `load()` падает с `MissingPluginException`.
class PairCredentials extends SvagaPlusCredentialStore {
  SvagaPlusCredentials? saved;

  @override
  Future<SvagaPlusCredentials?> load() async => saved;

  @override
  Future<void> save(SvagaPlusCredentials credentials) async => saved = credentials;

  @override
  Future<void> clear() async => saved = null;
}

/// Программируемый клиент: сценарий задаётся списком ответов на pollPairing.
class ScriptedApi extends SvagaPlusApiClient {
  final List<Object> pollScript;
  final Object? startError;
  int pollCalls = 0;
  int completeCalls = 0;

  ScriptedApi({this.pollScript = const [], this.startError})
    : super(baseUri: Uri.parse('https://example.test'));

  @override
  Future<SvagaPlusPairingStart> startPairing({
    String deviceName = 'Donaton Timer',
    String? platform,
    String? appVersion,
  }) async {
    if (startError != null) throw startError!;
    return SvagaPlusPairingStart(
      pairingId: 'p-1',
      userCode: '1234-5678',
      pairingSecret: 'secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      verificationUri: 'https://example.test/timer/connect?code=1234-5678',
      interval: 1,
    );
  }

  @override
  Future<SvagaPlusPairingPoll> pollPairing(String id, String secret) async {
    if (pollScript.isEmpty) {
      throw StateError('pollScript is empty — the test must script pollPairing');
    }
    // Последний шаг повторяется, чтобы тест мог опрашивать сколько угодно.
    final step = pollScript[pollCalls.clamp(0, pollScript.length - 1)];
    pollCalls++;
    if (step is! SvagaPlusPairingPoll) throw step;
    return step;
  }

  @override
  Future<void> completePairing(String id, SvagaPlusCredentials c) async {
    completeCalls++;
  }
}

/// `start`/`stop`/`dispose` переопределены, чтобы успешная привязка не
/// открывала настоящее socket_io-соединение на `example.test` — тот же
/// приём, что и `MemoryAdapter` в `svagaplus_provider_test.dart`.
class PairAdapter extends SvagaPlusAdapter {
  int starts = 0;
  int stops = 0;

  PairAdapter(SvagaPlusApiClient api)
    : super(
        api: api,
        credentials: const SvagaPlusCredentials(deviceId: 't', token: 't'),
        lastCursor: 0,
        appVersion: 'test',
      );

  @override
  void start() {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }

  @override
  Future<void> dispose() async {
    stops++;
  }
}

/// Проваливает первый вызов `startPairing`, затем успешен — прогоняет
/// настоящий цикл провал → `retryPairing()` → успех, а не только момент
/// синхронного сброса состояния.
class FlakyStartApi extends SvagaPlusApiClient {
  int startCalls = 0;

  FlakyStartApi() : super(baseUri: Uri.parse('https://example.test'));

  @override
  Future<SvagaPlusPairingStart> startPairing({
    String deviceName = 'Donaton Timer',
    String? platform,
    String? appVersion,
  }) async {
    startCalls++;
    if (startCalls == 1) throw const SvagaPlusHttpException(429);
    return SvagaPlusPairingStart(
      pairingId: 'p-retry',
      userCode: '1234-5678',
      pairingSecret: 'secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      verificationUri: 'https://example.test/timer/connect?code=1234-5678',
      interval: 1,
    );
  }

  @override
  Future<SvagaPlusPairingPoll> pollPairing(String id, String secret) async =>
      approved();

  @override
  Future<void> completePairing(String id, SvagaPlusCredentials c) async {}
}

SvagaPlusPairingPoll approved() => const SvagaPlusPairingPoll(
  pending: false,
  credentials: SvagaPlusCredentials(deviceId: 'dev-1', token: 'tok-1'),
  initialCursor: 42,
  interval: 1,
);

const pendingPoll = SvagaPlusPairingPoll(pending: true, interval: 1);

/// Интервал в несколько раз больше слайса отмены — чтобы тест на отклик
/// отмены (Finding 1) давал широкий, нефлейковый зазор: наивная отмена
/// «раз в интервал опроса» здесь заняла бы секунды, а нарезанная —
/// укладывается в пару слайсов по 250 мс.
const pendingPollSlow = SvagaPlusPairingPoll(pending: true, interval: 5);

/// Принимает любой `SvagaPlusApiClient` (не только `ScriptedApi`), чтобы
/// тест на ретрай после провала мог передать `FlakyStartApi`.
({SvagaPlusProvider provider, PairCredentials store}) makeProvider(
  SvagaPlusApiClient api, {
  bool openSucceeds = true,
}) {
  final storage = PairStorage();
  final store = PairCredentials();
  final provider = SvagaPlusProvider(
    storage: storage,
    timerProvider: TimerProvider(storage),
    donationService: PairDonationService(storage),
    api: api,
    credentialStore: store,
    adapter: PairAdapter(api),
    adapterFactory: (a, c, cursor) => PairAdapter(a),
  );
  provider.openUrl = (_) async => openSucceeds;
  return (provider: provider, store: store);
}

void main() {
  test('successful pairing saves credentials and enables the integration', () async {
    final api = ScriptedApi(pollScript: [pendingPoll, approved()]);
    final made = makeProvider(api);

    await made.provider.startPairing();

    expect(made.provider.pairing.state, SvagaPlusPairingState.done);
    expect(made.store.saved?.deviceId, 'dev-1');
    expect(made.provider.settings.enabled, isTrue);
    expect(made.provider.baselineCursor, 42);
    expect(api.completeCalls, 1);
    await made.provider.adapter.dispose();
  });

  test('a failed browser launch keeps the session alive', () async {
    final api = ScriptedApi(pollScript: [approved()]);
    final made = makeProvider(api, openSucceeds: false);

    await made.provider.startPairing();

    expect(made.provider.pairing.state, SvagaPlusPairingState.done);
    expect(api.pollCalls, greaterThan(0));
    await made.provider.adapter.dispose();
  });

  test('rate limiting surfaces as a typed failure, not an exception', () async {
    final api = ScriptedApi(startError: const SvagaPlusHttpException(429));
    final made = makeProvider(api);

    await made.provider.startPairing();

    expect(made.provider.pairing.state, SvagaPlusPairingState.failed);
    expect(made.provider.pairing.failure, SvagaPlusPairingFailure.rateLimited);
    expect(
      made.provider.pairing.failureKey,
      'svagaplus_pair_error_rate_limited',
    );
    await made.provider.adapter.dispose();
  });

  test('an expired code surfaces as expired', () async {
    final api = ScriptedApi(pollScript: [const SvagaPlusHttpException(410)]);
    final made = makeProvider(api);

    await made.provider.startPairing();

    expect(made.provider.pairing.failure, SvagaPlusPairingFailure.expired);
    await made.provider.adapter.dispose();
  });

  test('a transient server error is retried instead of aborting', () async {
    final api = ScriptedApi(
      pollScript: [const SvagaPlusHttpException(503), approved()],
    );
    final made = makeProvider(api);

    await made.provider.startPairing();

    expect(made.provider.pairing.state, SvagaPlusPairingState.done);
    expect(api.pollCalls, 2);
    await made.provider.adapter.dispose();
  });

  test('cancelling stops the loop and marks the session cancelled', () async {
    final api = ScriptedApi(pollScript: [pendingPoll]);
    final made = makeProvider(api);

    final pairing = made.provider.startPairing();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    made.provider.cancelPairing();
    await pairing;

    expect(made.provider.pairing.state, SvagaPlusPairingState.cancelled);
    expect(made.provider.settings.enabled, isFalse);
    await made.provider.adapter.dispose();
  });

  test('pairingInProgress still reflects the session for existing callers', () async {
    final api = ScriptedApi(pollScript: [approved()]);
    final made = makeProvider(api);

    expect(made.provider.pairingInProgress, isFalse);
    await made.provider.startPairing();
    expect(made.provider.pairingInProgress, isFalse);
    await made.provider.adapter.dispose();
  });

  test(
    'cancellation responds within a slice, not a full poll interval',
    () async {
      final api = ScriptedApi(pollScript: [pendingPollSlow]);
      final made = makeProvider(api);

      final pairing = made.provider.startPairing();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final stopwatch = Stopwatch()..start();
      made.provider.cancelPairing();
      await pairing;
      stopwatch.stop();

      expect(made.provider.pairing.state, SvagaPlusPairingState.cancelled);
      // Poll interval is 5s. An implementation that only checks the cancel
      // flag once per poll interval (i.e. no real slicing) would take close
      // to 5000ms to unwind here. A correctly sliced cancel responds within
      // a couple of 250ms slices. "Well under 1s" gives a wide margin on a
      // slow machine while still failing hard against a regression to
      // interval-only cancellation.
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      await made.provider.adapter.dispose();
    },
  );

  test(
    'retrying after a failure starts with a clean session, not a stale failure',
    () async {
      final api = FlakyStartApi();
      final made = makeProvider(api);

      await made.provider.startPairing();
      expect(made.provider.pairing.state, SvagaPlusPairingState.failed);
      expect(
        made.provider.pairing.failure,
        SvagaPlusPairingFailure.rateLimited,
      );

      final retry = made.provider.retryPairing();
      // startPairing resets to a fresh `SvagaPlusPairingSession(state:
      // starting)` synchronously, before its first `await` — so the stale
      // failure is already gone without waiting for the retry to settle.
      // This is the exact spot the copyWith-cannot-clear-null trap would
      // bite: copyWith would have carried the old failure forward instead.
      expect(made.provider.pairing.failure, isNull);
      expect(made.provider.pairing.failureKey, isNull);
      await retry;

      expect(made.provider.pairing.state, SvagaPlusPairingState.done);
      expect(made.provider.pairing.failure, isNull);
      expect(made.provider.pairing.failureKey, isNull);
      expect(api.startCalls, 2);
      await made.provider.adapter.dispose();
    },
  );
}
