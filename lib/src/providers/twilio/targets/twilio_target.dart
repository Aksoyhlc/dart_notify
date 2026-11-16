import '../../../core/notification/notification_target.dart';
import '../../../shared/utils/is_e164_phone_number.dart';

/// One SMS recipient in E.164 format, with a leading plus.
final class TwilioTarget implements NotificationTarget {
  TwilioTarget({required this.number}) {
    if (!isE164PhoneNumber(number)) {
      throw ArgumentError('Twilio target must be an E.164 number.');
    }
  }

  final String number;
}
