import '../../../shared/utils/validate_https_endpoint.dart';

final class IletimerkeziConfig {
  IletimerkeziConfig({
    required this.key,
    required this.hash,
    required this.sender,
    this.timeout = const Duration(seconds: 15),
    Uri? endpoint,
  }) : endpoint = endpoint ??
            Uri.parse('https://api.iletimerkezi.com/v1/send-sms/json') {
    if (key.trim().isEmpty ||
        key.contains('\r') ||
        key.contains('\n') ||
        hash.trim().isEmpty ||
        hash.contains('\r') ||
        hash.contains('\n')) {
      throw ArgumentError('İletimerkezi API key and hash are required.');
    }
    if (sender.trim().length < 3 ||
        sender.length > 11 ||
        sender.contains('\r') ||
        sender.contains('\n')) {
      throw ArgumentError('İletimerkezi sender must contain 3–11 characters.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    validateHttpsEndpoint(this.endpoint);
  }

  final String key;
  final String hash;
  final String sender;
  final Duration timeout;
  final Uri endpoint;
}
