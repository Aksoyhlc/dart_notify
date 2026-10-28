import '../../../core/notification/notification_target.dart';

final class ExpoPushTarget implements NotificationTarget {
  ExpoPushTarget({required Iterable<String> tokens})
      : tokens = List.unmodifiable(tokens.toSet()) {
    if (this.tokens.isEmpty) {
      throw ArgumentError('At least one Expo push token is required.');
    }
    for (final token in this.tokens) {
      if (!RegExp(r'^Expo(nent)?PushToken\[.+\]$').hasMatch(token)) {
        throw ArgumentError(
            'Expo push tokens must look like ExpoPushToken[...].');
      }
    }
  }

  final List<String> tokens;
}
