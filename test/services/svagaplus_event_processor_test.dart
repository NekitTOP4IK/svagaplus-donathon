import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';
import 'package:donaton_timer/providers/timer_provider.dart';
import 'package:donaton_timer/services/storage_service.dart';
import 'package:donaton_timer/services/svagaplus_event_processor.dart';

class ProcessorStorage extends StorageService {
  final applied = <String>{};
  @override
  Future<SvagaPlusMutationResult> applySvagaEvent({
    required event,
    required int seconds,
    required int currentDuration,
  }) async {
    if (!applied.add(event.id)) {
      return SvagaPlusMutationResult(
        changed: false,
        duration: currentDuration,
        appliedSeconds: seconds,
        status: 'applied',
      );
    }
    return SvagaPlusMutationResult(
      changed: true,
      duration: currentDuration + seconds,
      appliedSeconds: seconds,
      status: 'applied',
    );
  }
}

SvagaPlusSubscriptionEvent event(String id) => SvagaPlusSubscriptionEvent(
  id: id,
  cursor: id == 'a' ? 1 : 2,
  eventType: 'new_subscription',
  subscriberName: 'Alice',
  createdAt: DateTime.utc(2026, 7, 20),
);

void main() {
  test(
    'applies duplicate live/replay event once and acknowledges both deliveries',
    () async {
      final timer = TimerProvider(ProcessorStorage());
      var acknowledgements = 0;
      final processor = SvagaPlusEventProcessor(
        timerProvider: timer,
        acknowledge: (_) async => acknowledgements++,
      );
      const settings = SvagaPlusSettings(
        enabled: true,
        newSubscriptionSeconds: 900,
        renewedSubscriptionSeconds: 600,
      );

      final first = await processor.process(event('a'), settings);
      final duplicate = await processor.process(event('a'), settings);

      expect(first.applied, isTrue);
      expect(duplicate.duplicate, isTrue);
      expect(timer.duration, 900);
      expect(acknowledgements, 2);
    },
  );
}
