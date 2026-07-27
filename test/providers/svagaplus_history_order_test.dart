import 'package:flutter_test/flutter_test.dart';

import 'package:donaton_timer/models/svagaplus_history_entry.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/providers/svagaplus_provider.dart';
import 'package:donaton_timer/providers/timer_provider.dart';
import 'package:donaton_timer/services/donation_service.dart';
import 'package:donaton_timer/services/storage_service.dart';
import 'package:donaton_timer/services/svagaplus_adapter.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';
import 'package:donaton_timer/services/svagaplus_credential_store.dart';

class OrderStorage extends StorageService {
  final Map<String, dynamic> values;
  OrderStorage(this.values);

  @override
  Map<String, dynamic> loadSvagaHistory() => Map<String, dynamic>.from(values);

  @override
  int loadSvagaCursor() => 0;
}

class OrderApi extends SvagaPlusApiClient {
  OrderApi() : super(baseUri: Uri.parse('https://example.test'));
}

// flutter test has no native flutter_secure_storage backend registered on
// this platform (MissingPluginException), so the real credential store's
// storage dependency is swapped for a no-op fake via its existing DI seam.
// This does not touch what's under test (history ordering) — init() never
// reads real credentials here since autoConnect is false in every test.
class _NoopSecretStorage implements SvagaPlusSecretStorage {
  const _NoopSecretStorage();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

class OrderAdapter extends SvagaPlusAdapter {
  OrderAdapter()
    : super(
        api: OrderApi(),
        credentials: const SvagaPlusCredentials(deviceId: 't', token: 't'),
        lastCursor: 0,
        appVersion: 'test',
      );
}

SvagaPlusHistoryEntry entry(String id, int hour, int cursor) {
  final event = SvagaPlusSubscriptionEvent(
    id: id,
    cursor: cursor,
    eventType: 'new_subscription',
    subscriberName: id,
    createdAt: DateTime.utc(2026, 7, 20, hour),
  );
  return SvagaPlusHistoryEntry(
    event: event,
    appliedSeconds: 900,
    status: SvagaPlusHistoryStatus.applied,
    appliedAt: event.createdAt,
  );
}

SvagaPlusProvider makeProvider(List<SvagaPlusHistoryEntry> history) {
  final storage = OrderStorage({
    for (final item in history) item.event.id: item.toJson(),
  });
  return SvagaPlusProvider(
    storage: storage,
    timerProvider: TimerProvider(storage),
    donationService: DonationService(storage),
    api: OrderApi(),
    credentialStore: SvagaPlusCredentialStore(storage: const _NoopSecretStorage()),
    adapter: OrderAdapter(),
    initialHistory: history,
  );
}

void main() {
  test('history is sorted by createdAt descending', () async {
    final provider = makeProvider([
      entry('old', 9, 1),
      entry('newest', 18, 2),
      entry('middle', 13, 3),
    ]);
    await provider.init(autoConnect: false);

    expect(provider.history.map((e) => e.event.id).toList(), [
      'newest',
      'middle',
      'old',
    ]);
    await provider.adapter.dispose();
  });

  test('cursor breaks ties on identical createdAt', () async {
    final provider = makeProvider([
      entry('low-cursor', 12, 1),
      entry('high-cursor', 12, 9),
    ]);
    await provider.init(autoConnect: false);

    expect(provider.history.map((e) => e.event.id).toList(), [
      'high-cursor',
      'low-cursor',
    ]);
    await provider.adapter.dispose();
  });

  test('history is sorted immediately at construction, before init() runs', () {
    final provider = makeProvider([
      entry('old', 9, 1),
      entry('newest', 18, 2),
      entry('middle', 13, 3),
    ]);

    // No await, no init() — the getter must already reflect sorted order.
    expect(provider.history.map((e) => e.event.id).toList(), [
      'newest',
      'middle',
      'old',
    ]);
  });

  test('reading history repeatedly does not reorder or copy the backing list', () async {
    final provider = makeProvider([entry('a', 9, 1), entry('b', 18, 2)]);
    await provider.init(autoConnect: false);

    final first = provider.history;
    final second = provider.history;

    expect(first.map((e) => e.event.id).toList(), ['b', 'a']);
    expect(second.map((e) => e.event.id).toList(), ['b', 'a']);
    expect(() => first.add(entry('c', 20, 3)), throwsUnsupportedError);
    await provider.adapter.dispose();
  });
}
