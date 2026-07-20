import 'dart:async';

import '../models/svagaplus_settings.dart';
import '../models/svagaplus_subscription_event.dart';
import '../providers/timer_provider.dart';

export '../models/svagaplus_settings.dart';

class SvagaPlusProcessResult {
  final bool applied;
  final bool duplicate;
  const SvagaPlusProcessResult({
    required this.applied,
    required this.duplicate,
  });
}

typedef ProcessResult = SvagaPlusProcessResult;

class SvagaPlusEventProcessor {
  final TimerProvider timerProvider;
  final Function? acknowledge;
  final Future<void> Function(String eventId, int cursor)? acknowledgeCursor;
  Future<void> _tail = Future<void>.value();

  SvagaPlusEventProcessor({
    required this.timerProvider,
    this.acknowledge,
    this.acknowledgeCursor,
  }) : assert(acknowledge != null || acknowledgeCursor != null);

  Future<SvagaPlusProcessResult> process(
    SvagaPlusSubscriptionEvent event,
    SvagaPlusSettings settings,
  ) {
    final next = _tail.then((_) async {
      if (!settings.enabled) {
        return const SvagaPlusProcessResult(applied: false, duplicate: false);
      }
      final seconds = event.eventType == SvagaPlusEventType.newSubscription
          ? settings.newSubscriptionSeconds
          : settings.renewedSubscriptionSeconds;
      final result = await timerProvider.applySvagaEvent(event, seconds);
      if (acknowledgeCursor != null) {
        await acknowledgeCursor!(event.id, event.cursor);
      } else {
        await _invokeAcknowledge(event);
      }
      return SvagaPlusProcessResult(
        applied: result.changed,
        duplicate: !result.changed,
      );
    });
    _tail = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<void> _invokeAcknowledge(SvagaPlusSubscriptionEvent event) async {
    try {
      final result = Function.apply(acknowledge!, [event]);
      if (result is Future) await result;
    } on NoSuchMethodError {
      final result = Function.apply(acknowledge!, [event.id, event.cursor]);
      if (result is Future) await result;
    }
  }
}
