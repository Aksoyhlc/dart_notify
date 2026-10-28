import '../../../core/notification/notification_options.dart';
import '../enums/netgsm_encoding.dart';
import '../enums/netgsm_iys_filter.dart';
import '../utils/format_netgsm_date.dart';

final class NetgsmOptions implements NotificationOptions {
  NetgsmOptions({
    this.encoding = NetgsmEncoding.utf8,
    this.iysFilter = NetgsmIysFilter.informational,
    this.startAt,
    this.stopAt,
    this.referenceId,
  }) {
    for (final date in [startAt, stopAt]) {
      if (date != null && (date.year < 1000 || date.year > 9999)) {
        throw ArgumentError('SMS schedule years must have four digits.');
      }
    }
    if (startAt != null && stopAt != null) {
      // Compare wall-clock fields, irrespective of each DateTime's UTC flag.
      DateTime calendar(DateTime d) =>
          DateTime.utc(d.year, d.month, d.day, d.hour, d.minute);
      if (!calendar(stopAt!).isAfter(calendar(startAt!))) {
        throw ArgumentError('SMS stopAt must be after startAt.');
      }
    }
    if (referenceId != null && referenceId!.trim().isEmpty) {
      throw ArgumentError('SMS referenceId must not be blank.');
    }
  }

  final NetgsmEncoding encoding;
  final NetgsmIysFilter iysFilter;

  /// Calendar fields are interpreted as Netgsm-local time, at minute precision.
  final DateTime? startAt;
  final DateTime? stopAt;
  final String? referenceId;

  Map<String, Object?> toJson() => {
        'encoding': encoding.value,
        'iysfilter': iysFilter.value,
        if (startAt != null) 'startdate': formatNetgsmDate(startAt!),
        if (stopAt != null) 'stopdate': formatNetgsmDate(stopAt!),
        if (referenceId != null) 'referansID': referenceId,
      };
}
