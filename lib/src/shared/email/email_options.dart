import '../../core/notification/notification_options.dart';
import 'email_address.dart';

/// Delivery options independent of email recipient identity. Attachments are
/// message content and live on `NotifyMessage.attachments`.
final class EmailOptions implements NotificationOptions {
  EmailOptions({Iterable<EmailAddress> replyTo = const []})
      : replyTo = List.unmodifiable(replyTo);

  final List<EmailAddress> replyTo;
}
