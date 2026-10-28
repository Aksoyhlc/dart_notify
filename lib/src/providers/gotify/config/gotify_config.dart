import '../../../shared/utils/validate_https_endpoint.dart';

final class GotifyConfig {
  GotifyConfig({
    required this.baseUrl,
    this.clientToken,
    this.timeout = const Duration(seconds: 15),
  }) {
    validateHttpsEndpoint(baseUrl);
    if (clientToken != null &&
        (clientToken!.trim().isEmpty ||
            clientToken!.contains('\r') ||
            clientToken!.contains('\n'))) {
      throw ArgumentError('Gotify clientToken is invalid.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final Uri baseUrl;
  final String? clientToken;
  final Duration timeout;
}
