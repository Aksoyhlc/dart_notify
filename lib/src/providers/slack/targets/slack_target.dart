import '../../../core/notification/notification_target.dart';

final class SlackTarget implements NotificationTarget {
  SlackTarget({required this.channel}) {
    if (channel.trim().isEmpty ||
        channel.contains('\r') ||
        channel.contains('\n') ||
        channel.contains(' ')) {
      throw ArgumentError('Slack channel must be a channel ID or name.');
    }
  }

  final String channel;
}
