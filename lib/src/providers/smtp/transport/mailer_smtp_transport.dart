import 'dart:async';

import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import '../../../core/notification/notify_message.dart';
import '../config/smtp_config.dart';
import '../enums/smtp_security.dart';
import '../../../shared/email/email_address.dart';
import '../../../shared/email/email_options.dart';
import '../../../shared/email/email_target.dart';
import 'smtp_transport.dart';

/// Transport backed by the `mailer` Dart package.
final class MailerSmtpTransport implements SmtpTransport {
  const MailerSmtpTransport();

  @override
  Future<void> send({
    required SmtpConfig config,
    required NotifyMessage message,
    required EmailTarget target,
    EmailOptions? options,
  }) async {
    final server = SmtpServer(
      config.host,
      port: config.port,
      username: config.username,
      password: config.password,
      ssl: config.security == SmtpSecurity.sslTls,
      allowInsecure: config.security == SmtpSecurity.none,
      ignoreBadCertificate: false,
    );
    mailer.Address toAddress(EmailAddress a) =>
        mailer.Address(a.address, a.name);
    final email = mailer.Message()
      ..from = toAddress(config.from)
      ..recipients.addAll(target.to.map(toAddress))
      ..ccRecipients.addAll(target.cc.map(toAddress))
      ..bccRecipients.addAll(target.bcc.map(toAddress))
      ..subject = message.title ?? '(no subject)'
      ..text = message.body;
    if (message.htmlBody != null) email.html = message.htmlBody;
    if (options != null && options.replyTo.isNotEmpty) {
      email.headers['Reply-To'] = options.replyTo.map(toAddress).toList();
    }
    if (message.attachments.isNotEmpty) {
      email.attachments.addAll([
        for (final attachment in message.attachments)
          mailer.StreamAttachment(
            Stream<List<int>>.value(attachment.bytes),
            attachment.contentType,
            fileName: attachment.fileName,
          ),
      ]);
    }
    await mailer.send(email, server, timeout: config.timeout);
  }
}
