import '../../../core/notification/notification_options.dart';
import '../enums/expo_priority.dart';

final class ExpoPushOptions implements NotificationOptions {
  ExpoPushOptions({
    this.sound,
    this.badge,
    this.channelId,
    this.categoryId,
    this.ttl,
    this.expiration,
    this.priority,
    this.subtitle,
    this.mutableContent,
    Map<String, Object?> data = const {},
  }) : data = Map.unmodifiable(data) {
    if (ttl != null && ttl! <= Duration.zero) {
      throw ArgumentError('Expo ttl must be positive.');
    }
  }

  final String? sound;
  final int? badge;
  final String? channelId;
  final String? categoryId;
  final Duration? ttl;
  final DateTime? expiration;
  final ExpoPriority? priority;
  final String? subtitle;
  final bool? mutableContent;
  final Map<String, Object?> data;
}
