import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:donaton_timer/models/svagaplus_pairing_session.dart';
import 'package:donaton_timer/providers/localization_provider.dart';
import 'package:donaton_timer/widgets/svagaplus_pairing_panel.dart';

late final LocalizationProvider ru;

Widget harness(
  SvagaPlusPairingSession session, {
  VoidCallback? onCancel,
  VoidCallback? onRetry,
  ValueChanged<Uri>? onOpen,
}) => MaterialApp(
  home: Scaffold(
    body: SvagaPlusPairingPanel(
      session: session,
      localization: ru,
      onCancel: onCancel ?? () {},
      onRetry: onRetry ?? () {},
      onOpen: onOpen ?? (_) {},
    ),
  ),
);

SvagaPlusPairingSession awaiting({bool browserOpened = true}) =>
    SvagaPlusPairingSession(
      state: SvagaPlusPairingState.awaiting,
      userCode: '1234-5678',
      verificationUri: Uri.parse('https://example.test/timer/connect?code=1234-5678'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 8)),
      browserOpened: browserOpened,
    );

void main() {
  setUpAll(() async {
    ru = LocalizationProvider();
    await ru.init('ru');
  });

  testWidgets('shows the code, the countdown and a cancel button', (tester) async {
    await tester.pumpWidget(harness(awaiting()));
    await tester.pump();

    expect(find.text('1234-5678'), findsOneWidget);
    expect(find.textContaining('Код истекает через'), findsOneWidget);
    expect(find.text('Отменить привязку'), findsOneWidget);
  });

  testWidgets('cancel button invokes the callback', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(harness(awaiting(), onCancel: () => cancelled++));
    await tester.pump();

    await tester.tap(find.text('Отменить привязку'));
    await tester.pump();

    expect(cancelled, 1);
  });

  testWidgets('hints to open manually when the browser did not launch', (tester) async {
    await tester.pumpWidget(harness(awaiting(browserOpened: false)));
    await tester.pump();

    expect(
      find.text('Браузер не открылся сам — откройте ссылку вручную'),
      findsOneWidget,
    );
  });

  testWidgets('open button passes the verification uri back', (tester) async {
    Uri? opened;
    await tester.pumpWidget(harness(awaiting(), onOpen: (uri) => opened = uri));
    await tester.pump();

    await tester.tap(find.text('Открыть в браузере'));
    await tester.pump();

    expect(opened?.queryParameters['code'], '1234-5678');
  });

  testWidgets('a failure shows the human message and a retry button', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      harness(
        const SvagaPlusPairingSession(
          state: SvagaPlusPairingState.failed,
          failure: SvagaPlusPairingFailure.rateLimited,
        ),
        onRetry: () => retried++,
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Слишком много попыток. Подождите несколько минут и попробуйте снова',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Попробовать снова'));
    await tester.pump();
    expect(retried, 1);
  });

  testWidgets('an idle session renders nothing', (tester) async {
    await tester.pumpWidget(harness(SvagaPlusPairingSession.idle));
    await tester.pump();

    expect(find.text('Отменить привязку'), findsNothing);
    expect(find.textContaining('Код'), findsNothing);
  });
}
