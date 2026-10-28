import '../../../shared/email/email_address.dart';

final class ResendConfig {
  ResendConfig({
    required this.apiKey,
    required this.from,
    this.endpoint,
    this.timeout = const Duration(seconds: 20),
  }) {
    if (apiKey.trim().isEmpty ||
        apiKey.contains('\r') ||
        apiKey.contains('\n')) {
      throw ArgumentError('Resend API key is invalid.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final String apiKey;
  final EmailAddress from;
  final Uri? endpoint;
  final Duration timeout;
}
