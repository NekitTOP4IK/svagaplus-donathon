import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/donation_record.dart';
import 'package:donaton_timer/models/feed_entry.dart';
import 'package:donaton_timer/models/svagaplus_history_entry.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/services/donation_feed.dart';

DonationRecord donation(String name, int hour, {int minutes = 5}) =>
    DonationRecord(
      username: name,
      minutesAdded: minutes,
      timestamp: DateTime.utc(2026, 7, 20, hour),
      serviceName: 'DonationAlerts',
      amount: 100.0,
      currency: 'RUB',
    );

SvagaPlusHistoryEntry sub(
  String id,
  int hour, {
  int cursor = 1,
  int appliedSeconds = 900,
  SvagaPlusHistoryStatus status = SvagaPlusHistoryStatus.applied,
  String type = 'new_subscription',
}) {
  final event = SvagaPlusSubscriptionEvent(
    id: id,
    cursor: cursor,
    eventType: type,
    subscriberName: 'sub-$id',
    createdAt: DateTime.utc(2026, 7, 20, hour),
  );
  return SvagaPlusHistoryEntry(
    event: event,
    appliedSeconds: appliedSeconds,
    status: status,
    appliedAt: event.createdAt,
  );
}

void main() {
  test('interleaves both sources newest first', () {
    final feed = buildFeed(
      [donation('d-late', 15), donation('d-early', 11)],
      [sub('s-mid', 13, cursor: 2), sub('s-oldest', 9, cursor: 1)],
      limit: 10,
    );

    expect(feed.map((e) => e.username).toList(), [
      'd-late',
      'sub-s-mid',
      'd-early',
      'sub-s-oldest',
    ]);
  });

  test('stops at limit without touching the rest', () {
    final feed = buildFeed(
      [donation('d1', 15), donation('d2', 14), donation('d3', 13)],
      [sub('s1', 12, cursor: 1)],
      limit: 2,
    );

    expect(feed.length, 2);
    expect(feed.map((e) => e.username).toList(), ['d1', 'd2']);
  });

  test('returns empty list for non-positive limit', () {
    expect(buildFeed([donation('d1', 15)], [sub('s1', 14)], limit: 0), isEmpty);
    expect(buildFeed([donation('d1', 15)], [sub('s1', 14)], limit: -3), isEmpty);
  });

  test('handles either side being empty', () {
    expect(
      buildFeed([], [sub('s1', 14, cursor: 1)], limit: 5).single.username,
      'sub-s1',
    );
    expect(buildFeed([donation('d1', 15)], [], limit: 5).single.username, 'd1');
    expect(buildFeed([], [], limit: 5), isEmpty);
  });

  test('donation wins when timestamps are equal', () {
    final feed = buildFeed(
      [donation('same-donation', 12)],
      [sub('same-sub', 12, cursor: 1)],
      limit: 5,
    );

    expect(feed.first.source, FeedSource.donation);
    expect(feed.last.source, FeedSource.svagaPlus);
  });

  test('maps subscription fields including kind, minutes and reverted', () {
    final feed = buildFeed(
      [],
      [
        sub('renewed', 15, cursor: 3, appliedSeconds: 600, type: 'renewed_subscription'),
        sub(
          'cancelled',
          14,
          cursor: 2,
          appliedSeconds: 900,
          status: SvagaPlusHistoryStatus.reverted,
        ),
      ],
      limit: 5,
    );

    expect(feed[0].kind, FeedKind.renewedSubscription);
    expect(feed[0].minutesAdded, 10);
    expect(feed[0].reverted, isFalse);
    expect(feed[0].eventId, 'renewed');
    expect(feed[0].amount, isNull);

    expect(feed[1].kind, FeedKind.newSubscription);
    expect(feed[1].minutesAdded, 15);
    expect(feed[1].reverted, isTrue);
  });

  test('rounds odd applied seconds to nearest minute', () {
    final feed = buildFeed([], [sub('odd', 12, appliedSeconds: 90)], limit: 5);
    expect(feed.single.minutesAdded, 2);
  });

  test('maps donation money fields through', () {
    final feed = buildFeed([donation('d1', 12, minutes: 7)], [], limit: 5);
    final entry = feed.single;

    expect(entry.source, FeedSource.donation);
    expect(entry.kind, FeedKind.donation);
    expect(entry.minutesAdded, 7);
    expect(entry.serviceName, 'DonationAlerts');
    expect(entry.amount, 100.0);
    expect(entry.currency, 'RUB');
    expect(entry.reverted, isFalse);
  });

  test('asserts when donations are not sorted newest-first', () {
    // Ascending order (earliest first) violates the documented precondition.
    final unsortedDonations = [donation('d-early', 11), donation('d-late', 15)];

    expect(
      () => buildFeed(unsortedDonations, [], limit: 5),
      throwsA(isA<AssertionError>()),
    );
  });

  test('asserts when svagaHistory is not sorted newest-first', () {
    // Ascending order (earliest first) violates the documented precondition.
    final unsortedHistory = [sub('s-old', 9, cursor: 1), sub('s-new', 13, cursor: 2)];

    expect(
      () => buildFeed([], unsortedHistory, limit: 5),
      throwsA(isA<AssertionError>()),
    );
  });
}
