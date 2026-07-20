enum SvagaPlusEventType { newSubscription, renewedSubscription }

class SvagaPlusSubscriptionEvent {
  final String id;
  final int cursor;
  final SvagaPlusEventType eventType;
  final String subscriberName;
  final int? telegramUserId;
  final String? subscriptionId;
  final DateTime createdAt;

  SvagaPlusSubscriptionEvent({
    required this.id,
    required this.cursor,
    required Object eventType,
    required this.subscriberName,
    required this.createdAt,
    this.telegramUserId,
    this.subscriptionId,
  }) : eventType = _parseType(eventType);

  static SvagaPlusEventType _parseType(Object value) {
    if (value == SvagaPlusEventType.newSubscription ||
        value == 'new_subscription') {
      return SvagaPlusEventType.newSubscription;
    }
    if (value == SvagaPlusEventType.renewedSubscription ||
        value == 'renewed_subscription') {
      return SvagaPlusEventType.renewedSubscription;
    }
    throw const FormatException('Unknown SVAGA+ event type');
  }

  SvagaPlusEventType get type => eventType;

  factory SvagaPlusSubscriptionEvent.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final cursor = json['cursor'];
    final type = json['event_type'];
    final name = json['subscriber_name'];
    final createdAt = DateTime.tryParse('${json['created_at'] ?? ''}');
    if (id is! String ||
        id.isEmpty ||
        cursor is! int ||
        cursor <= 0 ||
        type is! String ||
        (type != 'new_subscription' && type != 'renewed_subscription') ||
        name is! String ||
        createdAt == null) {
      throw const FormatException('Invalid SVAGA+ timer event');
    }
    return SvagaPlusSubscriptionEvent(
      id: id,
      cursor: cursor,
      eventType: type,
      subscriberName: name,
      telegramUserId: (json['telegram_user_id'] as num?)?.toInt(),
      subscriptionId: json['subscription_id'] as String?,
      createdAt: createdAt,
    );
  }

  String get wireEventType => eventType == SvagaPlusEventType.newSubscription
      ? 'new_subscription'
      : 'renewed_subscription';

  Map<String, dynamic> toJson() => {
    'id': id,
    'cursor': cursor,
    'event_type': wireEventType,
    'subscriber_name': subscriberName,
    'telegram_user_id': telegramUserId,
    'subscription_id': subscriptionId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
}
