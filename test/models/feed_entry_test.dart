import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/feed_entry.dart';

void main() {
  test('donation entry carries service data and is never reverted', () {
    final entry = FeedEntry(
      source: FeedSource.donation,
      kind: FeedKind.donation,
      username: 'Alice',
      minutesAdded: 15,
      timestamp: DateTime.utc(2026, 7, 20, 12),
      serviceName: 'DonationAlerts',
      amount: 500.0,
      currency: 'RUB',
    );

    expect(entry.reverted, isFalse);
    expect(entry.eventId, isNull);
    expect(entry.serviceName, 'DonationAlerts');
  });

  test('subscription entry carries eventId and no money fields', () {
    final entry = FeedEntry(
      source: FeedSource.svagaPlus,
      kind: FeedKind.newSubscription,
      username: 'Bob',
      minutesAdded: 15,
      timestamp: DateTime.utc(2026, 7, 20, 12),
      reverted: true,
      eventId: 'evt-1',
    );

    expect(entry.eventId, 'evt-1');
    expect(entry.amount, isNull);
    expect(entry.serviceName, isNull);
    expect(entry.reverted, isTrue);
  });

  test('donation with subscription kind is rejected', () {
    expect(
      () => FeedEntry(
        source: FeedSource.donation,
        kind: FeedKind.newSubscription,
        username: 'Alice',
        minutesAdded: 15,
        timestamp: DateTime.utc(2026, 7, 20, 12),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('subscription without eventId is rejected', () {
    expect(
      () => FeedEntry(
        source: FeedSource.svagaPlus,
        kind: FeedKind.newSubscription,
        username: 'Bob',
        minutesAdded: 15,
        timestamp: DateTime.utc(2026, 7, 20, 12),
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  test('subscription with money fields is rejected', () {
    expect(
      () => FeedEntry(
        source: FeedSource.svagaPlus,
        kind: FeedKind.renewedSubscription,
        username: 'Bob',
        minutesAdded: 10,
        timestamp: DateTime.utc(2026, 7, 20, 12),
        amount: 100.0,
        eventId: 'evt-2',
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
