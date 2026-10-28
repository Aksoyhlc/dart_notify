import '../../../core/notification/notification_target.dart';
import '../../../shared/utils/normalize_tr_phone_number.dart';

final class IletimerkeziTarget implements NotificationTarget {
  IletimerkeziTarget({required Iterable<String> numbers})
      : numbers =
            List.unmodifiable(numbers.map(normalizeTrPhoneNumber).toSet()) {
    if (this.numbers.isEmpty) {
      throw ArgumentError('At least one SMS recipient is required.');
    }
  }

  final List<String> numbers;
}
