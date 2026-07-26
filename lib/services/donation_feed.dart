import '../models/donation_record.dart';
import '../models/feed_entry.dart';
import '../models/svagaplus_history_entry.dart';
import '../models/svagaplus_subscription_event.dart';

/// Сливает донаты и историю SVAGA+ в одну ленту, свежее сверху.
///
/// Предусловие: оба входа уже отсортированы по убыванию времени —
/// [donations] по `timestamp`, [svagaHistory] по `event.createdAt`.
/// Функция не сортирует, а сливает двумя указателями и выходит, набрав
/// [limit] элементов — это O(limit), а не O(n log n).
///
/// При равных метках времени первым идёт донат.
List<FeedEntry> buildFeed(
  List<DonationRecord> donations,
  List<SvagaPlusHistoryEntry> svagaHistory, {
  required int limit,
}) {
  if (limit <= 0) return const <FeedEntry>[];

  assert(() {
    for (var i = 1; i < donations.length; i++) {
      if (donations[i - 1].timestamp.isBefore(donations[i].timestamp)) return false;
    }
    for (var i = 1; i < svagaHistory.length; i++) {
      if (svagaHistory[i - 1].event.createdAt
          .isBefore(svagaHistory[i].event.createdAt)) {
        return false;
      }
    }
    return true;
  }(), 'buildFeed: оба входа должны быть отсортированы свежее-сверху');

  final feed = <FeedEntry>[];
  var d = 0;
  var s = 0;

  while (feed.length < limit &&
      (d < donations.length || s < svagaHistory.length)) {
    final takeDonation =
        s >= svagaHistory.length ||
        (d < donations.length &&
            !donations[d].timestamp.isBefore(svagaHistory[s].event.createdAt));

    if (takeDonation) {
      feed.add(_fromDonation(donations[d]));
      d++;
    } else {
      feed.add(_fromSubscription(svagaHistory[s]));
      s++;
    }
  }

  return feed;
}

FeedEntry _fromDonation(DonationRecord record) => FeedEntry(
  source: FeedSource.donation,
  kind: FeedKind.donation,
  username: record.username,
  minutesAdded: record.minutesAdded,
  timestamp: record.timestamp,
  serviceName: record.serviceName,
  amount: record.amount,
  currency: record.currency,
);

FeedEntry _fromSubscription(SvagaPlusHistoryEntry entry) => FeedEntry(
  source: FeedSource.svagaPlus,
  kind: entry.event.eventType == SvagaPlusEventType.newSubscription
      ? FeedKind.newSubscription
      : FeedKind.renewedSubscription,
  username: entry.event.subscriberName,
  minutesAdded: (entry.appliedSeconds / 60).round(),
  timestamp: entry.event.createdAt,
  reverted: entry.status == SvagaPlusHistoryStatus.reverted,
  eventId: entry.event.id,
);
