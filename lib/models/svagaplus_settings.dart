class SvagaPlusSettings {
  final bool enabled;
  final int newSubscriptionSeconds;
  final int renewedSubscriptionSeconds;
  final String? deviceId;
  final String? deviceName;

  const SvagaPlusSettings({
    this.enabled = false,
    this.newSubscriptionSeconds = 900,
    this.renewedSubscriptionSeconds = 900,
    this.deviceId,
    this.deviceName,
  });

  SvagaPlusSettings copyWith({
    bool? enabled,
    int? newSubscriptionSeconds,
    int? renewedSubscriptionSeconds,
    String? deviceId,
    String? deviceName,
    bool clearDeviceId = false,
    bool clearDeviceName = false,
  }) => SvagaPlusSettings(
    enabled: enabled ?? this.enabled,
    newSubscriptionSeconds:
        newSubscriptionSeconds ?? this.newSubscriptionSeconds,
    renewedSubscriptionSeconds:
        renewedSubscriptionSeconds ?? this.renewedSubscriptionSeconds,
    deviceId: clearDeviceId ? null : deviceId ?? this.deviceId,
    deviceName: clearDeviceName ? null : deviceName ?? this.deviceName,
  );

  factory SvagaPlusSettings.fromJson(Map<String, dynamic> json) {
    int seconds(String key, int fallback) {
      final value = json[key];
      return value is num && value.toInt() >= 0 ? value.toInt() : fallback;
    }

    return SvagaPlusSettings(
      enabled: json['enabled'] as bool? ?? false,
      newSubscriptionSeconds: seconds('newSubscriptionSeconds', 900),
      renewedSubscriptionSeconds: seconds('renewedSubscriptionSeconds', 900),
      deviceId: json['deviceId'] as String?,
      deviceName: json['deviceName'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'newSubscriptionSeconds': newSubscriptionSeconds,
    'renewedSubscriptionSeconds': renewedSubscriptionSeconds,
    'deviceId': deviceId,
    'deviceName': deviceName,
  };

  @override
  bool operator ==(Object other) =>
      other is SvagaPlusSettings &&
      other.enabled == enabled &&
      other.newSubscriptionSeconds == newSubscriptionSeconds &&
      other.renewedSubscriptionSeconds == renewedSubscriptionSeconds &&
      other.deviceId == deviceId &&
      other.deviceName == deviceName;

  @override
  int get hashCode => Object.hash(
    enabled,
    newSubscriptionSeconds,
    renewedSubscriptionSeconds,
    deviceId,
    deviceName,
  );
}
