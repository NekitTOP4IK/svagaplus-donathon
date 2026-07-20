import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/config/app_config.dart';

void main() {
  test('defaults to the staging SVAGA+ endpoint', () {
    expect(AppConfig.environment, 'staging');
    expect(
      AppConfig.svagaPlusBaseUrl,
      'https://svaga-staging.nekittop4ik.qzz.io',
    );
    expect(AppConfig.svagaPlusWebSocketUri.scheme, 'wss');
  });

  test('builds endpoint paths without duplicate separators', () {
    expect(
      AppConfig.svagaPlusEndpoint('/api/timer/events', {
        'after': '42',
      }).toString(),
      'https://svaga-staging.nekittop4ik.qzz.io/api/timer/events?after=42',
    );
  });
}
