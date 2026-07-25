import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/models/svagaplus_history_entry.dart';
import 'package:donaton_timer/providers/localization_provider.dart';
import 'package:donaton_timer/providers/svagaplus_provider.dart';
import 'package:donaton_timer/providers/timer_provider.dart';
import 'package:donaton_timer/screens/svagaplus_history_screen.dart';
import 'package:donaton_timer/services/donation_service.dart';
import 'package:donaton_timer/services/svagaplus_adapter.dart';
import 'package:donaton_timer/services/svagaplus_api_client.dart';
import 'package:donaton_timer/services/svagaplus_credential_store.dart';
import 'package:donaton_timer/services/storage_service.dart';

class HistoryStorage extends StorageService {
  final Map<String, dynamic> values;

  HistoryStorage(this.values);

  @override
  Map<String, dynamic> loadSvagaHistory() => Map<String, dynamic>.from(values);
}

class HistoryDonationService extends DonationService {
  HistoryDonationService(super.storage);
}

class HistoryApi extends SvagaPlusApiClient {
  HistoryApi() : super(baseUri: Uri.parse('https://example.test'));
}

class HistoryCredentials extends SvagaPlusCredentialStore {}

class HistoryAdapter extends SvagaPlusAdapter {
  HistoryAdapter()
    : super(
        api: HistoryApi(),
        credentials: const SvagaPlusCredentials(
          deviceId: 'test',
          token: 'test',
        ),
        lastCursor: 0,
        appVersion: 'test',
      );
}

class CountingTimerProvider extends TimerProvider {
  int revertCalls = 0;
  int restoreCalls = 0;
  final Completer<SvagaPlusMutationResult>? pendingRevert;

  CountingTimerProvider(StorageService storage, {this.pendingRevert})
    : super(storage);

  @override
  Future<SvagaPlusMutationResult> revertSvagaEvent(String eventId) {
    revertCalls++;
    return pendingRevert?.future ??
        Future.value(
          const SvagaPlusMutationResult(
            changed: true,
            duration: 0,
            appliedSeconds: 900,
            status: 'reverted',
          ),
        );
  }

  @override
  Future<SvagaPlusMutationResult> restoreSvagaEvent(String eventId) {
    restoreCalls++;
    return Future.value(
      const SvagaPlusMutationResult(
        changed: true,
        duration: 900,
        appliedSeconds: 900,
        status: 'applied',
      ),
    );
  }
}

SvagaPlusHistoryEntry entry(String id, SvagaPlusHistoryStatus status) {
  final event = SvagaPlusSubscriptionEvent(
    id: id,
    cursor: id == 'applied' ? 2 : 1,
    eventType: 'new_subscription',
    subscriberName: id == 'applied' ? 'Alice' : 'Bob',
    createdAt: DateTime.utc(2026, 7, 20, 12, 30),
  );
  return SvagaPlusHistoryEntry(
    event: event,
    appliedSeconds: 900,
    status: status,
    appliedAt: event.createdAt,
  );
}

Future<Widget> harness(
  SvagaPlusProvider provider,
  LocalizationProvider localization,
) async {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: provider),
      ChangeNotifierProvider.value(value: localization),
    ],
    child: MaterialApp(home: const SvagaPlusHistoryScreen()),
  );
}

SvagaPlusProvider makeHistoryProvider(
  CountingTimerProvider timer,
  List<SvagaPlusHistoryEntry> history,
) {
  final storage = HistoryStorage({
    for (final entry in history) entry.event.id: entry.toJson(),
  });
  final donation = HistoryDonationService(storage);
  return SvagaPlusProvider(
    storage: storage,
    timerProvider: timer,
    donationService: donation,
    api: HistoryApi(),
    credentialStore: HistoryCredentials(),
    adapter: HistoryAdapter(),
    initialHistory: history,
  );
}

late final LocalizationProvider russianLocalization;

void main() {
  setUpAll(() async {
    russianLocalization = LocalizationProvider();
    await russianLocalization.init('ru');
  });
  testWidgets('renders applied and reverted rows with exact Russian actions', (
    tester,
  ) async {
    final timer = CountingTimerProvider(HistoryStorage({}));
    final provider = makeHistoryProvider(timer, [
      entry('applied', SvagaPlusHistoryStatus.applied),
      entry('reverted', SvagaPlusHistoryStatus.reverted),
    ]);
    final localization = russianLocalization;

    await tester.pumpWidget(await harness(provider, localization));
    await tester.pump();

    expect(find.text('Учтено'), findsOneWidget);
    expect(find.text('Отменено'), findsOneWidget);
    expect(find.text('Отменить'), findsOneWidget);
    expect(find.text('Вернуть'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Новая подписка'), findsNWidgets(2));
    expect(find.textContaining('2026'), findsNWidgets(2));
    expect(find.text('+00:15:00'), findsNWidgets(2));
    await provider.adapter.dispose();
  });

  testWidgets(
    'cancel and restore call timer mutations and lock a pending button',
    (tester) async {
      final pending = Completer<SvagaPlusMutationResult>();
      final timer = CountingTimerProvider(
        HistoryStorage({}),
        pendingRevert: pending,
      );
      final provider = makeHistoryProvider(timer, [
        entry('applied', SvagaPlusHistoryStatus.applied),
        entry('reverted', SvagaPlusHistoryStatus.reverted),
      ]);
      final localization = russianLocalization;

      await tester.pumpWidget(await harness(provider, localization));
      await tester.pump();
      await tester.tap(find.text('Отменить'));
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Отменить'));
      await tester.pump();

      expect(timer.revertCalls, 1);
      expect(find.text('Отменить'), findsOneWidget);
      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Отменить'),
      );
      expect(cancelButton.onPressed, isNull);

      pending.complete(
        const SvagaPlusMutationResult(
          changed: true,
          duration: 0,
          appliedSeconds: 900,
          status: 'reverted',
        ),
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Вернуть').last);
      await tester.pump();
      expect(timer.restoreCalls, 1);
      await provider.adapter.dispose();
    },
  );
}
