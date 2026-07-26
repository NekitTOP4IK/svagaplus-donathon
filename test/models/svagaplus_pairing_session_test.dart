import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_pairing_session.dart';

void main() {
  test('idle session is not in progress and has no failure', () {
    const session = SvagaPlusPairingSession.idle;

    expect(session.state, SvagaPlusPairingState.idle);
    expect(session.inProgress, isFalse);
    expect(session.failureKey, isNull);
    expect(session.browserOpened, isFalse);
  });

  test('starting, awaiting and completing count as in progress', () {
    for (final state in [
      SvagaPlusPairingState.starting,
      SvagaPlusPairingState.awaiting,
      SvagaPlusPairingState.completing,
    ]) {
      expect(
        SvagaPlusPairingSession(state: state).inProgress,
        isTrue,
        reason: '$state must be in progress',
      );
    }
  });

  test('terminal states are not in progress', () {
    for (final state in [
      SvagaPlusPairingState.idle,
      SvagaPlusPairingState.done,
      SvagaPlusPairingState.failed,
      SvagaPlusPairingState.cancelled,
    ]) {
      expect(
        SvagaPlusPairingSession(state: state).inProgress,
        isFalse,
        reason: '$state must not be in progress',
      );
    }
  });

  test('every failure maps to a distinct localization key', () {
    final keys = <String>{};
    for (final failure in SvagaPlusPairingFailure.values) {
      final key = SvagaPlusPairingSession(
        state: SvagaPlusPairingState.failed,
        failure: failure,
      ).failureKey;
      expect(key, isNotNull, reason: '$failure has no key');
      expect(key, startsWith('svagaplus_pair_error_'));
      keys.add(key!);
    }
    expect(keys.length, SvagaPlusPairingFailure.values.length);
  });

  test('copyWith preserves untouched fields', () {
    final session = SvagaPlusPairingSession(
      state: SvagaPlusPairingState.awaiting,
      userCode: '1234-5678',
      verificationUri: Uri.parse('https://example.test/timer/connect?code=1234-5678'),
      expiresAt: DateTime.utc(2026, 7, 26, 12),
      browserOpened: true,
    );

    final completing = session.copyWith(state: SvagaPlusPairingState.completing);

    expect(completing.state, SvagaPlusPairingState.completing);
    expect(completing.userCode, '1234-5678');
    expect(completing.browserOpened, isTrue);
    expect(completing.expiresAt, DateTime.utc(2026, 7, 26, 12));
  });
}
