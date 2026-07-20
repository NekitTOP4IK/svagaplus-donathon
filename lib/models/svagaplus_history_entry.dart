import 'svagaplus_subscription_event.dart';

enum SvagaPlusHistoryStatus { applied, reverted }

class SvagaPlusHistoryEntry {
  final SvagaPlusSubscriptionEvent event;
  final int appliedSeconds;
  final SvagaPlusHistoryStatus status;
  final DateTime appliedAt;
  final DateTime? revertedAt;

  const SvagaPlusHistoryEntry({
    required this.event,
    required this.appliedSeconds,
    required this.status,
    required this.appliedAt,
    this.revertedAt,
  });

  factory SvagaPlusHistoryEntry.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    final appliedSeconds = json['appliedSeconds'];
    final appliedAt = DateTime.tryParse('${json['appliedAt'] ?? ''}');
    if (status is! String ||
        (status != 'applied' && status != 'reverted') ||
        appliedSeconds is! num ||
        appliedSeconds.toInt() < 0 ||
        appliedAt == null ||
        json['event'] is! Map) {
      throw const FormatException('Invalid SVAGA+ history entry');
    }
    return SvagaPlusHistoryEntry(
      event: SvagaPlusSubscriptionEvent.fromJson(
        Map<String, dynamic>.from(json['event'] as Map),
      ),
      appliedSeconds: appliedSeconds.toInt(),
      status: status == 'reverted'
          ? SvagaPlusHistoryStatus.reverted
          : SvagaPlusHistoryStatus.applied,
      appliedAt: appliedAt,
      revertedAt: json['revertedAt'] == null
          ? null
          : DateTime.tryParse('${json['revertedAt']}'),
    );
  }

  Map<String, dynamic> toJson() => {
    'event': event.toJson(),
    'appliedSeconds': appliedSeconds,
    'status': status.name,
    'appliedAt': appliedAt.toUtc().toIso8601String(),
    'revertedAt': revertedAt?.toUtc().toIso8601String(),
  };

  SvagaPlusHistoryEntry copyWith({
    SvagaPlusHistoryStatus? status,
    DateTime? revertedAt,
    bool clearRevertedAt = false,
  }) => SvagaPlusHistoryEntry(
    event: event,
    appliedSeconds: appliedSeconds,
    status: status ?? this.status,
    appliedAt: appliedAt,
    revertedAt: clearRevertedAt ? null : revertedAt ?? this.revertedAt,
  );
}
