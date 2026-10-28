import '../../../core/notification/notification_target.dart';

final class GotifyTarget implements NotificationTarget {
  GotifyTarget({required this.appToken}) {
    if (appToken.trim().isEmpty || appToken.contains(RegExp(r'\s'))) {
      throw ArgumentError('Gotify appToken must be a nonblank token.');
    }
  }

  /// The application token identifies the destination; it is not a credential
  /// for other applications.
  final String appToken;
}
