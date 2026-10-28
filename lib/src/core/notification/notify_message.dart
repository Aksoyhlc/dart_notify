import '../enums/notify_priority.dart';
import 'notify_attachment.dart';

/// Provider-independent content. [data] is consumed by providers that support
/// structured metadata (such as OneSignal); SMTP does not serialize it.
final class NotifyMessage {
  NotifyMessage({
    required this.body,
    this.title,
    this.htmlBody,
    this.priority = NotifyPriority.normal,
    Map<String, Object?> data = const {},
    Iterable<NotifyAttachment> attachments = const [],
  })  : data = Map.unmodifiable(data),
        attachments = List.unmodifiable(attachments) {
    if (body.trim().isEmpty && (htmlBody?.trim().isEmpty ?? true)) {
      throw ArgumentError('At least body or htmlBody must be non-empty.');
    }
    if (title != null &&
        (title!.trim().isEmpty ||
            title!.contains('\r') ||
            title!.contains('\n'))) {
      throw ArgumentError.value(title, 'title', 'Must not be blank.');
    }
  }

  final String? title;
  final String body;
  final String? htmlBody;
  final NotifyPriority priority;
  final Map<String, Object?> data;

  /// Immutable attachment list. Providers without attachment support reject
  /// the send instead of dropping files.
  final List<NotifyAttachment> attachments;
}
