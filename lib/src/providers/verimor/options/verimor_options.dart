import '../../../core/notification/notification_options.dart';
import '../enums/verimor_datacoding.dart';
import '../enums/verimor_iys_recipient_type.dart';

final class VerimorOptions implements NotificationOptions {
  VerimorOptions({
    this.datacoding = VerimorDatacoding.gsmBasic,
    this.validFor = const Duration(hours: 24),
    this.sendAt,
    this.customId,
    this.commercial = false,
    this.iysRecipientType,
  }) {
    if (validFor < const Duration(minutes: 1) ||
        validFor > const Duration(hours: 48)) {
      throw ArgumentError(
          'Verimor validFor must be between 1 minute and 48 hours.');
    }
    if (validFor.inMicroseconds % const Duration(minutes: 1).inMicroseconds !=
        0) {
      throw ArgumentError('Verimor validFor must use whole-minute precision.');
    }
    if (sendAt != null) {
      if (sendAt!.isUtc) {
        throw ArgumentError(
            'sendAt must be a Türkiye-local calendar time, not UTC.');
      }
      if (sendAt!.year < 1000 || sendAt!.year > 9999) {
        throw ArgumentError('sendAt must have a four-digit year.');
      }
    }
    if (customId != null &&
        (customId!.trim().isEmpty || customId!.length > 50)) {
      throw ArgumentError('Verimor customId must be 1-50 characters.');
    }
    if (commercial && iysRecipientType == null) {
      throw ArgumentError(
          'Verimor commercial messages require an IYS recipient type.');
    }
  }

  final VerimorDatacoding datacoding;
  final Duration validFor;
  final DateTime? sendAt;
  final String? customId;
  final bool commercial;
  final VerimorIysRecipientType? iysRecipientType;
}
