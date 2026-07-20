import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/svagaplus_subscription_event.dart';

void main() {
  test('subscription event parses the server contract', () {
    final event = SvagaPlusSubscriptionEvent.fromJson({
      'id': 'event-1',
      'cursor': 42,
      'event_type': 'renewed_subscription',
      'subscriber_name': 'Alice',
      'created_at': '2026-07-20T14:30:00Z',
    });
    expect(event.cursor, 42);
    expect(event.eventType, SvagaPlusEventType.renewedSubscription);
  });

  test('unknown event type and non-positive cursor are rejected', () {
    final json = {
      'id': 'event-1',
      'cursor': 1,
      'event_type': 'other',
      'subscriber_name': 'Alice',
      'created_at': '2026-07-20T14:30:00Z',
    };
    expect(
      () => SvagaPlusSubscriptionEvent.fromJson(json),
      throwsFormatException,
    );
    expect(
      () => SvagaPlusSubscriptionEvent.fromJson({
        ...json,
        'event_type': 'new_subscription',
        'cursor': 0,
      }),
      throwsFormatException,
    );
  });
}
