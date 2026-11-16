import '../../../core/notification/notification_target.dart';
import '../../../shared/utils/is_e164_phone_number.dart';

/// One WhatsApp user identified by an international phone number.
final class WhatsAppTarget implements NotificationTarget {
  WhatsAppTarget({required String number})
      : number = number.startsWith('+') ? number : '+$number' {
    if (!isE164PhoneNumber(this.number)) {
      throw ArgumentError('WhatsApp target must be an E.164 number.');
    }
  }

  final String number;
}
