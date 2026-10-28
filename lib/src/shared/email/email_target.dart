import '../../core/notification/notification_target.dart';
import 'email_address.dart';

final class EmailTarget implements NotificationTarget {
  EmailTarget({
    required Iterable<EmailAddress> to,
    Iterable<EmailAddress> cc = const [],
    Iterable<EmailAddress> bcc = const [],
  })  : to = List.unmodifiable(to),
        cc = List.unmodifiable(cc),
        bcc = List.unmodifiable(bcc) {
    if (this.to.isEmpty && this.cc.isEmpty && this.bcc.isEmpty) {
      throw ArgumentError('EmailTarget requires at least one recipient');
    }
  }

  final List<EmailAddress> to;
  final List<EmailAddress> cc;
  final List<EmailAddress> bcc;
}
