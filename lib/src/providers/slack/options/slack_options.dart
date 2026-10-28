import '../../../core/notification/notification_options.dart';

final class SlackOptions implements NotificationOptions {
  SlackOptions({
    Iterable<Map<String, Object?>> blocks = const [],
    this.threadTs,
    this.mrkdwn = true,
    this.unfurlLinks = false,
    this.unfurlMedia = false,
    this.username,
    this.iconEmoji,
  }) : blocks = List.unmodifiable(
            blocks.map((block) => Map<String, Object?>.unmodifiable(block)));

  /// Raw Block Kit maps; the package validates shape, not block semantics.
  final List<Map<String, Object?>> blocks;
  final String? threadTs;
  final bool mrkdwn;
  final bool unfurlLinks;
  final bool unfurlMedia;
  final String? username;
  final String? iconEmoji;
}
