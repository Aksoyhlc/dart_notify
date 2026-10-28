import '../../../core/notification/notification_options.dart';

final class GotifyOptions implements NotificationOptions {
  GotifyOptions({this.priority, this.markdown = false}) {
    if (priority != null && (priority! < 0 || priority! > 10)) {
      throw ArgumentError('Gotify priority must be between 0 and 10.');
    }
  }

  final int? priority;
  final bool markdown;
}
