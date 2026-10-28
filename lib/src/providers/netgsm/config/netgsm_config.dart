import '../../../shared/utils/validate_https_endpoint.dart';

final class NetgsmConfig {
  NetgsmConfig({
    required this.username,
    required this.password,
    required this.sender,
    this.appName,
    this.partnerCode,
    this.timeout = const Duration(seconds: 15),
    Uri? endpoint,
  }) : endpoint = endpoint ??
            Uri.parse('https://api.netgsm.com.tr/sms/rest/v2/send') {
    if (username.trim().isEmpty ||
        username.contains(':') ||
        username.contains('\r') ||
        username.contains('\n') ||
        password.isEmpty) {
      throw ArgumentError('Netgsm credentials are invalid.');
    }
    if (sender.trim().length < 3 ||
        sender.length > 11 ||
        sender.contains('\r') ||
        sender.contains('\n')) {
      throw ArgumentError('Netgsm sender must contain 3–11 characters.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    validateHttpsEndpoint(this.endpoint);
  }

  final String username;
  final String password;
  final String sender;
  final String? appName;
  final String? partnerCode;
  final Duration timeout;
  final Uri endpoint;
}
