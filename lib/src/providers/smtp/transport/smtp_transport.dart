import '../../../core/notification/notify_message.dart';
import '../config/smtp_config.dart';
import '../../../shared/email/email_options.dart';
import '../../../shared/email/email_target.dart';

/// Pluggable SMTP transport, primarily useful for tests and custom adapters.
abstract interface class SmtpTransport {
  Future<void> send({
    required SmtpConfig config,
    required NotifyMessage message,
    required EmailTarget target,
    EmailOptions? options,
  });
}
