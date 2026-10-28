import '../../../core/notification/notification_target.dart';

final class TelegramTarget implements NotificationTarget {
  TelegramTarget({required this.chatId}) {
    if (!RegExp(r'^(-?\d+|@[A-Za-z0-9_]{5,})$').hasMatch(chatId)) {
      throw ArgumentError(
          'Telegram chatId must be a numeric chat ID or an @channel username.');
    }
  }

  final String chatId;
}
