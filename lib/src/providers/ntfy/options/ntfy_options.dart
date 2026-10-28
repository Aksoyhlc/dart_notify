import '../../../core/notification/notification_options.dart';
import '../enums/ntfy_priority.dart';
import '../utils/format_ntfy_delay.dart';

final class NtfyOptions implements NotificationOptions {
  NtfyOptions({
    this.priority,
    Iterable<String> tags = const [],
    this.click,
    this.icon,
    this.markdown = false,
    this.delay,
    this.attachUrl,
  }) : tags = List.unmodifiable(tags) {
    if (this.tags.any((tag) => tag.trim().isEmpty || tag.contains(' '))) {
      throw ArgumentError('Ntfy tags must be nonblank and contain no spaces.');
    }
    if (delay != null) formatNtfyDelay(delay!);
  }

  final NtfyPriority? priority;
  final List<String> tags;
  final Uri? click;
  final Uri? icon;
  final bool markdown;
  final Duration? delay;

  /// Remote file the ntfy server fetches; local bytes are not supported.
  final Uri? attachUrl;
}
