/// Откуда пришла строка ленты.
enum FeedSource { donation, svagaPlus }

/// Что именно произошло.
enum FeedKind { donation, newSubscription, renewedSubscription }

/// Строка объединённой ленты «Последние донаты».
///
/// Вью-модель: не сериализуется и никуда не сохраняется. Источник истины
/// для донатов — `Statistics`, для подписок — история SVAGA+.
class FeedEntry {
  final FeedSource source;
  final FeedKind kind;
  final String username;
  final int minutesAdded;
  final DateTime timestamp;

  /// Только для [FeedSource.donation].
  final String? serviceName;
  final double? amount;
  final String? currency;

  /// Только для [FeedSource.svagaPlus].
  final bool reverted;
  final String? eventId;

  const FeedEntry({
    required this.source,
    required this.kind,
    required this.username,
    required this.minutesAdded,
    required this.timestamp,
    this.serviceName,
    this.amount,
    this.currency,
    this.reverted = false,
    this.eventId,
  }) : assert(
         source != FeedSource.donation ||
             (kind == FeedKind.donation && !reverted && eventId == null),
         'Донат не может быть отменён, иметь eventId или другой kind',
       ),
       assert(
         source != FeedSource.svagaPlus ||
             (kind != FeedKind.donation &&
                 serviceName == null &&
                 amount == null &&
                 currency == null &&
                 eventId != null),
         'У подписки не бывает сервиса и суммы, но обязателен eventId',
       );
}
