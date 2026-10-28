import '../../../shared/utils/validate_https_endpoint.dart';

final class TelegramConfig {
  TelegramConfig({
    required this.botToken,
    this.timeout = const Duration(seconds: 15),
    Uri? endpoint,
  }) : endpoint = endpoint ?? Uri.parse('https://api.telegram.org') {
    if (!RegExp(r'^\d+:[A-Za-z0-9_-]+$').hasMatch(botToken)) {
      throw ArgumentError('Telegram bot token is invalid.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    validateHttpsEndpoint(this.endpoint);
  }

  final String botToken;
  final Duration timeout;
  final Uri endpoint;
}
