import '../../../core/notification/notification_options.dart';
import '../enums/telegram_parse_mode.dart';

final class TelegramOptions implements NotificationOptions {
  TelegramOptions({
    this.parseMode = TelegramParseMode.plain,
    this.silent = false,
    this.protectContent = false,
    this.threadId,
    this.replyToMessageId,
    this.disableLinkPreview = false,
  }) {
    if (threadId != null && threadId! < 1) {
      throw ArgumentError('threadId must be positive.');
    }
    if (replyToMessageId != null && replyToMessageId! < 1) {
      throw ArgumentError('replyToMessageId must be positive.');
    }
  }

  final TelegramParseMode parseMode;
  final bool silent;
  final bool protectContent;
  final int? threadId;
  final int? replyToMessageId;
  final bool disableLinkPreview;
}
