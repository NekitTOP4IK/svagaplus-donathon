import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/models/app_settings.dart';
import 'package:donaton_timer/models/svagaplus_settings.dart';

void main() {
  test('SVAGA+ defaults are disabled and fifteen minutes', () {
    const settings = SvagaPlusSettings();
    expect(settings.enabled, isFalse);
    expect(settings.newSubscriptionSeconds, 900);
    expect(settings.renewedSubscriptionSeconds, 900);
  });

  test('old AppSettings JSON loads default SVAGA+ settings', () {
    final settings = AppSettings.fromJson(const {});
    expect(settings.svagaPlusSettings, const SvagaPlusSettings());
  });

  test('SVAGA+ settings round-trip device identity', () {
    const settings = SvagaPlusSettings(
      enabled: true,
      newSubscriptionSeconds: 1200,
      renewedSubscriptionSeconds: 1800,
      deviceId: 'device-1',
      deviceName: 'Streaming PC',
    );
    expect(SvagaPlusSettings.fromJson(settings.toJson()), settings);
  });
}
