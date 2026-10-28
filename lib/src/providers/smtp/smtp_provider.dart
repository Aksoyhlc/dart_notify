import 'dart:async';
import 'dart:io';

import 'package:mailer/mailer.dart' as mailer;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import 'config/smtp_config.dart';
import '../../shared/email/email_options.dart';
import '../../shared/email/email_target.dart';
import 'transport/mailer_smtp_transport.dart';
import 'transport/smtp_transport.dart';

final class SmtpProvider
    extends NotificationProvider<EmailTarget, EmailOptions> {
  SmtpProvider({
    required this.id,
    required this.config,
    SmtpTransport? transport,
  }) : _transport = transport ?? const MailerSmtpTransport() {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID required');
  }

  @override
  final String id;
  final SmtpConfig config;
  final SmtpTransport _transport;

  /// SMTP submission is not generally idempotent. The client may lose its
  /// response after the server accepted a message, so retries could duplicate.
  @override
  bool get supportsSafeRetry => false;

  @override
  bool get supportsAttachments => true;

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required EmailTarget target,
    required DeliveryContext context,
    EmailOptions? options,
  }) async {
    try {
      await _transport.send(
        config: config,
        message: message,
        target: target,
        options: options,
      );
      return const ProviderResponse.accepted();
    } on mailer.SmtpClientAuthenticationException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.failed,
        error: DeliveryError(
            code: 'smtp_auth', message: 'SMTP authentication failed.'),
      );
    } on mailer.SmtpMessageValidationException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.failed,
        error: DeliveryError(
            code: 'smtp_invalid_message',
            message: 'SMTP message was rejected during validation.'),
      );
    } on mailer.SmtpClientCommunicationException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
            code: 'smtp_protocol',
            message:
                'SMTP transaction failed; acceptance status may be unknown.'),
      );
    } on mailer.MailerException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
            code: 'smtp_error',
            message: 'SMTP error; acceptance status may be unknown.'),
      );
    } on TimeoutException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
            code: 'smtp_timeout',
            message: 'SMTP timed out; acceptance status unknown.'),
      );
    } on SocketException {
      throw const NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
            code: 'smtp_network',
            message: 'SMTP network error; acceptance status unknown.'),
      );
    }
  }
}
