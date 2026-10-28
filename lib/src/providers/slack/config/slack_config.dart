import '../../../shared/utils/validate_https_endpoint.dart';

final class SlackConfig {
  SlackConfig({
    required this.token,
    this.timeout = const Duration(seconds: 15),
    Uri? endpoint,
  }) : endpoint =
            endpoint ?? Uri.parse('https://slack.com/api/chat.postMessage') {
    if (token.trim().isEmpty ||
        token.contains('\r') ||
        token.contains('\n') ||
        token.contains(' ')) {
      throw ArgumentError('Slack token is invalid.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    validateHttpsEndpoint(this.endpoint);
  }

  final String token;
  final Duration timeout;
  final Uri endpoint;
}
