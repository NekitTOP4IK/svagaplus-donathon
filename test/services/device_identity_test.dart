import 'package:flutter_test/flutter_test.dart';
import 'package:donaton_timer/services/device_identity.dart';

void main() {
  test('device name includes the hostname', () {
    expect(defaultDeviceName(hostname: 'NEKIT-PC'), 'Donaton Timer · NEKIT-PC');
  });

  test('device name falls back when the hostname is blank', () {
    expect(defaultDeviceName(hostname: '   '), 'Donaton Timer');
    expect(defaultDeviceName(hostname: ''), 'Donaton Timer');
  });

  test('device name is truncated to the column limit', () {
    final name = defaultDeviceName(hostname: 'X' * 200);
    expect(name.length, 120);
    expect(name, startsWith('Donaton Timer · XXX'));
  });

  test('platform names are humanised', () {
    expect(currentPlatformName(operatingSystem: 'windows'), 'Windows');
    expect(currentPlatformName(operatingSystem: 'macos'), 'macOS');
    expect(currentPlatformName(operatingSystem: 'linux'), 'Linux');
    expect(currentPlatformName(operatingSystem: 'fuchsia'), 'fuchsia');
  });
}
