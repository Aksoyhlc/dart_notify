import '../../../core/notification/notification_target.dart';

final class NtfyTarget implements NotificationTarget {
  NtfyTarget({required this.topic}) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(topic)) {
      throw ArgumentError(
          'Ntfy topic must be 1-64 characters of letters, digits, _ or -.');
    }
  }

  final String topic;
}
