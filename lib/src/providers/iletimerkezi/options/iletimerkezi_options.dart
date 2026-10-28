import '../../../core/notification/notification_options.dart';
import '../enums/iletimerkezi_iys.dart';

final class IletimerkeziOptions implements NotificationOptions {
  IletimerkeziOptions({
    this.iys = IletimerkeziIys.transactional,
    this.sendAt,
  }) {
    if (sendAt != null) {
      if (sendAt!.isUtc) {
        throw ArgumentError(
            'sendAt must be a Türkiye-local calendar time, not UTC.');
      }
      if (sendAt!.year < 1000 || sendAt!.year > 9999) {
        throw ArgumentError('sendAt must have a four-digit year.');
      }
    }
  }

  final IletimerkeziIys iys;

  /// Calendar fields are interpreted as Türkiye local time at minute precision.
  final DateTime? sendAt;
}
