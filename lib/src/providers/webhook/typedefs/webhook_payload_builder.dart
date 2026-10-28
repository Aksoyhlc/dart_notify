import '../../../core/notification/notify_message.dart';

typedef WebhookPayloadBuilder = Map<String, Object?> Function(
    NotifyMessage message);
