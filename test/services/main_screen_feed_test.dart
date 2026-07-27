import 'package:flutter_test/flutter_test.dart';

import 'package:donaton_timer/models/donation_record.dart';
import 'package:donaton_timer/models/feed_entry.dart';
import 'package:donaton_timer/models/svagaplus_history_entry.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/services/donation_feed.dart';

SvagaPlusHistoryEntry sub(String id, int hour, int cursor) {
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

void main() {
  test('screen-sized feed keeps ten newest across both sources', () {
    final donations = [
      // 9, not 8: the pool (9 donations + 2 history) must exceed limit: 10
      // so the merge actually has something to push out. At 8 the pool
      // equals the limit and nothing can be excluded, making
      // isNot(contains('s-old')) below unsatisfiable regardless of
      // buildFeed's correctness.
      for (var i = 0; i < 9; i++)
        DonationRecord(
          username: 'd$i',
          minutesAdded: 5,
          timestamp: DateTime.utc(2026, 7, 20, 23 - i),
          serviceName: 'DonationAlerts',
          amount: 100.0,
          currency: 'RUB',
        ),
    ];
    final history = [sub('s-new', 22, 2), sub('s-old', 3, 1)];

    final feed = buildFeed(donations, history, limit: 10);

    expect(feed.length, 10);
    expect(feed.first.username, 'd0');
    expect(feed.map((e) => e.username), contains('s-new'));
    expect(feed.map((e) => e.username), isNot(contains('s-old')));
    expect(
      feed.where((e) => e.source == FeedSource.svagaPlus).length,
      1,
    );
  });

  test('feed falls back to donations only when there is no history', () {
    final feed = buildFeed(
      [
        DonationRecord(
          username: 'only',
          minutesAdded: 3,
          timestamp: DateTime.utc(2026, 7, 20, 12),
          serviceName: 'DonationAlerts',
          amount: 50.0,
          currency: 'RUB',
        ),
      ],
      const [],
      limit: 10,
    );

    expect(feed.single.username, 'only');
    expect(feed.single.source, FeedSource.donation);
  });
}
