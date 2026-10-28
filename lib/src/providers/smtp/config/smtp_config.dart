import '../enums/smtp_security.dart';
import '../../../shared/email/email_address.dart';

final class SmtpConfig {
  SmtpConfig({
    required this.host,
    required this.from,
    this.port = 587,
    this.security = SmtpSecurity.startTlsRequired,
    this.username,
    this.password,
    this.timeout = const Duration(seconds: 20),
  }) {
    if (host.trim().isEmpty || host.contains('\r') || host.contains('\n')) {
      throw ArgumentError('Invalid SMTP host');
    }
    if (port < 1 || port > 65535) throw ArgumentError('Invalid SMTP port');
    if ((username == null) != (password == null)) {
      throw ArgumentError('SMTP username/password must be provided together');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive');
    }
  }

  final String host;
  final int port;
  final SmtpSecurity security;
  final String? username;
  final String? password;
  final EmailAddress from;
  final Duration timeout;
}
