import '../../../shared/utils/validate_https_endpoint.dart';

final class VerimorConfig {
  VerimorConfig({
    required this.username,
    required this.password,
    required this.sourceAddr,
    this.timeout = const Duration(seconds: 15),
    Uri? endpoint,
  }) : endpoint =
            endpoint ?? Uri.parse('https://sms.verimor.com.tr/v2/send.json') {
    if (!RegExp(r'^[0-9]{10,12}$').hasMatch(username)) {
      throw ArgumentError(
          'Verimor username must be the numeric account number.');
    }
    if (password.isEmpty ||
        password.contains('\r') ||
        password.contains('\n')) {
      throw ArgumentError('Verimor password is required.');
    }
    if (sourceAddr.trim().length < 3 ||
        sourceAddr.length > 11 ||
        sourceAddr.contains('\r') ||
        sourceAddr.contains('\n')) {
      throw ArgumentError('Verimor sourceAddr must contain 3–11 characters.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    validateHttpsEndpoint(this.endpoint);
  }

  final String username;
  final String password;
  final String sourceAddr;
  final Duration timeout;
  final Uri endpoint;
}
