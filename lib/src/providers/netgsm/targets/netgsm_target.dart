import '../../../core/notification/notification_target.dart';
import '../utils/normalize_netgsm_number.dart';

final class NetgsmTarget implements NotificationTarget {
  NetgsmTarget({required Iterable<String> numbers})
      : numbers =
            List.unmodifiable(numbers.map(normalizeNetgsmNumber).toSet()) {
    if (this.numbers.isEmpty) {
      throw ArgumentError('At least one SMS recipient is required.');
    }
  }

  final List<String> numbers;
}
