import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:donaton_timer/models/feed_entry.dart';
import 'package:donaton_timer/providers/localization_provider.dart';
import 'package:donaton_timer/widgets/donation_feed_list.dart';

late final LocalizationProvider ru;

FeedEntry donationEntry() => FeedEntry(
  source: FeedSource.donation,
  kind: FeedKind.donation,
  username: 'Donator',
  minutesAdded: 5,
  timestamp: DateTime.utc(2026, 7, 20, 15),
  serviceName: 'DonationAlerts',
  amount: 100.0,
  currency: 'RUB',
);

FeedEntry subscriptionEntry({
  bool reverted = false,
  FeedKind kind = FeedKind.newSubscription,
  String id = 'evt-1',
  String name = 'Subscriber',
}) => FeedEntry(
  source: FeedSource.svagaPlus,
  kind: kind,
  username: name,
  minutesAdded: 15,
  timestamp: DateTime.utc(2026, 7, 20, 14),
  reverted: reverted,
  eventId: id,
);

Widget harness(List<FeedEntry> entries) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      height: 300,
      child: DonationFeedList(entries: entries, localization: ru),
    ),
  ),
);

void main() {
  setUpAll(() async {
    ru = LocalizationProvider();
    await ru.init('ru');
  });

  testWidgets('shows the SVAGA+ badge only on subscription rows', (
    tester,
  ) async {
    await tester.pumpWidget(harness([donationEntry(), subscriptionEntry()]));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Donator'), findsOneWidget);
    expect(find.text('Subscriber'), findsOneWidget);
    expect(find.text('Новая подписка'), findsOneWidget);
  });

  testWidgets('labels renewals with the renewal string', (tester) async {
    await tester.pumpWidget(
      harness([subscriptionEntry(kind: FeedKind.renewedSubscription)]),
    );
    await tester.pump();

    expect(find.text('Продление подписки'), findsOneWidget);
  });

  testWidgets('strikes through a reverted subscription', (tester) async {
    await tester.pumpWidget(harness([subscriptionEntry(reverted: true)]));
    await tester.pump();

    final name = tester.widget<Text>(find.text('Subscriber'));
    expect(name.style?.decoration, TextDecoration.lineThrough);

    final minutes = tester.widget<Text>(find.text('+15 min'));
    expect(minutes.style?.decoration, TextDecoration.lineThrough);
    expect(minutes.style?.color, Colors.grey);
  });

  testWidgets('leaves an applied subscription unstruck and green', (
    tester,
  ) async {
    await tester.pumpWidget(harness([subscriptionEntry()]));
    await tester.pump();

    final minutes = tester.widget<Text>(find.text('+15 min'));
    expect(minutes.style?.decoration, isNull);
    expect(minutes.style?.color, Colors.green);
  });

  testWidgets('shows the empty placeholder when there is nothing', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const []));
    await tester.pump();

    expect(find.text('Нет донатов'), findsOneWidget);
  });
}
