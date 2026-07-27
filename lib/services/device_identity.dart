import 'dart:io';

/// Максимум, который принимает колонка `timer_pairing_requests.device_name`.
const deviceNameMaxLength = 120;

/// Имя, под которым устройство появится в списке на сайте.
///
/// [hostname] передаётся только в тестах; в приложении берётся
/// `Platform.localHostname`.
String defaultDeviceName({String? hostname}) {
  final host = (hostname ?? Platform.localHostname).trim();
  final name = host.isEmpty ? 'Donaton Timer' : 'Donaton Timer · $host';
  return name.length <= deviceNameMaxLength
      ? name
      : name.substring(0, deviceNameMaxLength);
}

/// Человекочитаемое имя платформы для карточки устройства.
///
/// [operatingSystem] передаётся только в тестах.
String currentPlatformName({String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  return switch (os) {
    'windows' => 'Windows',
    'macos' => 'macOS',
    'linux' => 'Linux',
    _ => os,
  };
}
