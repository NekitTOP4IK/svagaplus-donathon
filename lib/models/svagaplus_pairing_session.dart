/// Фаза привязки устройства.
enum SvagaPlusPairingState {
  idle,
  starting,
  awaiting,
  completing,
  done,
  failed,
  cancelled,
}

/// Почему привязка не удалась.
///
/// Отдельного `consumed` нет намеренно: сервер отвечает 410 и на истёкший,
/// и на уже использованный код, различая их только текстом тела, которое
/// клиент не разбирает.
enum SvagaPlusPairingFailure {
  rateLimited,
  expired,
  invalidSecret,
  unauthorized,
  network,
  unknown,
}

/// Состояние текущей попытки привязки.
///
/// Заменяет прежний булев флаг: UI нужно знать не только «идёт или нет»,
/// но и код, ссылку, срок и причину провала — чтобы не показывать сырые
/// статус-коды.
class SvagaPlusPairingSession {
  final SvagaPlusPairingState state;
  final String? userCode;
  final Uri? verificationUri;
  final DateTime? expiresAt;

  /// Удалось ли открыть ссылку в браузере. При `false` UI подсвечивает
  /// кнопку «Открыть в браузере» — сессия при этом жива.
  final bool browserOpened;

  final SvagaPlusPairingFailure? failure;

  const SvagaPlusPairingSession({
    this.state = SvagaPlusPairingState.idle,
    this.userCode,
    this.verificationUri,
    this.expiresAt,
    this.browserOpened = false,
    this.failure,
  });

  static const idle = SvagaPlusPairingSession();

  bool get inProgress =>
      state == SvagaPlusPairingState.starting ||
      state == SvagaPlusPairingState.awaiting ||
      state == SvagaPlusPairingState.completing;

  /// Ключ локализации для причины провала.
  String? get failureKey => switch (failure) {
    null => null,
    SvagaPlusPairingFailure.rateLimited => 'svagaplus_pair_error_rate_limited',
    SvagaPlusPairingFailure.expired => 'svagaplus_pair_error_expired',
    SvagaPlusPairingFailure.invalidSecret => 'svagaplus_pair_error_invalid',
    SvagaPlusPairingFailure.unauthorized => 'svagaplus_pair_error_unauthorized',
    SvagaPlusPairingFailure.network => 'svagaplus_pair_error_network',
    SvagaPlusPairingFailure.unknown => 'svagaplus_pair_error_unknown',
  };

  SvagaPlusPairingSession copyWith({
    SvagaPlusPairingState? state,
    String? userCode,
    Uri? verificationUri,
    DateTime? expiresAt,
    bool? browserOpened,
    SvagaPlusPairingFailure? failure,
  }) => SvagaPlusPairingSession(
    state: state ?? this.state,
    userCode: userCode ?? this.userCode,
    verificationUri: verificationUri ?? this.verificationUri,
    expiresAt: expiresAt ?? this.expiresAt,
    browserOpened: browserOpened ?? this.browserOpened,
    failure: failure ?? this.failure,
  );
}
