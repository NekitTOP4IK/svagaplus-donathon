/// Build-time configuration for external services.
class AppConfig {
  static const environment = String.fromEnvironment(
    'SVAGAPLUS_ENV',
    defaultValue: 'staging',
  );

  /// Defaults to staging so local builds cannot accidentally target production.
  static const svagaPlusBaseUrl = String.fromEnvironment(
    'SVAGAPLUS_BASE_URL',
    defaultValue: 'https://svaga-staging.nekittop4ik.qzz.io',
  );

  static Uri get svagaPlusUri => Uri.parse(svagaPlusBaseUrl);

  static Uri get svagaPlusWebSocketUri {
    final scheme = svagaPlusUri.scheme == 'https' ? 'wss' : 'ws';
    return svagaPlusUri.replace(scheme: scheme);
  }

  static Uri svagaPlusEndpoint(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return svagaPlusUri.replace(
      path: '${svagaPlusUri.path}$normalized',
      queryParameters: query,
    );
  }
}
