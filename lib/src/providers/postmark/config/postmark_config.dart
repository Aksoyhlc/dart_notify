import '../../../shared/email/email_address.dart';

/// Credentials and sender defaults for the Postmark single-email API.
final class PostmarkConfig {
  PostmarkConfig({
    required this.serverToken,
    required this.from,
    this.messageStream,
    this.timeout = const Duration(seconds: 15),
  }) {
    if (serverToken.isEmpty || RegExp(r'[^\x21-\x7e]').hasMatch(serverToken)) {
      throw ArgumentError('Postmark serverToken is invalid.');
    }
    if (messageStream != null && messageStream!.trim().isEmpty) {
      throw ArgumentError('Postmark messageStream must not be blank.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final String serverToken;
  final EmailAddress from;
  final String? messageStream;
  final Duration timeout;
}
