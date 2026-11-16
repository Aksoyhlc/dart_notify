import '../../../core/notification/notification_target.dart';

/// A Pushover user or group key, optionally restricted to named devices.
final class PushoverTarget implements NotificationTarget {
  PushoverTarget({
    required this.userKey,
    Iterable<String> devices = const [],
  }) : devices = List.unmodifiable(devices) {
    if (!RegExp(r'^[A-Za-z0-9]{30}$').hasMatch(userKey)) {
      throw ArgumentError('Pushover userKey must be a 30-character key.');
    }
    final deviceName = RegExp(r'^[A-Za-z0-9_-]{1,25}$');
    if (this.devices.any((device) => !deviceName.hasMatch(device))) {
      throw ArgumentError('Pushover device name is invalid.');
    }
  }

  final String userKey;
  final List<String> devices;
}
