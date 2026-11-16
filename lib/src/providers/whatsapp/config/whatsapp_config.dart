/// Credentials for a registered WhatsApp Business phone number.
final class WhatsAppConfig {
  WhatsAppConfig({
    required this.phoneNumberId,
    required this.accessToken,
    required this.graphApiVersion,
    this.messagingAccountId,
    this.timeout = const Duration(seconds: 15),
  }) {
    if (!RegExp(r'^[0-9]+$').hasMatch(phoneNumberId)) {
      throw ArgumentError('WhatsApp phoneNumberId must contain only digits.');
    }
    if (!RegExp(r'^[A-Za-z0-9._~+/=-]+$').hasMatch(accessToken)) {
      throw ArgumentError('WhatsApp accessToken is invalid.');
    }
    if (!RegExp(r'^v[1-9][0-9]*\.[0-9]+$').hasMatch(graphApiVersion)) {
      throw ArgumentError('WhatsApp graphApiVersion must look like v25.0.');
    }
    if (messagingAccountId?.trim().isEmpty ?? false) {
      throw ArgumentError('WhatsApp messagingAccountId must not be blank.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final String phoneNumberId;
  final String accessToken;
  final String graphApiVersion;

  /// Selects the Messaging account when the token can access more than one.
  final String? messagingAccountId;
  final Duration timeout;
}
