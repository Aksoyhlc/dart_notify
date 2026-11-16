import '../../../core/notification/notification_options.dart';
import '../../../shared/utils/validate_https_endpoint.dart';
import '../enums/pushover_priority.dart';

final class PushoverOptions implements NotificationOptions {
  PushoverOptions({
    this.priority,
    this.html = false,
    this.sound,
    this.url,
    this.urlTitle,
    this.ttl,
    this.retryEvery,
    this.expireAfter,
    this.acknowledgementCallback,
  }) {
    final link = url;
    if (link != null &&
        (!link.isAbsolute || link.toString().runes.length > 512)) {
      throw ArgumentError(
          'Pushover url must be absolute and at most 512 characters.');
    }
    if (urlTitle != null && (link == null || urlTitle!.runes.length > 100)) {
      throw ArgumentError(
          'Pushover urlTitle requires a URL and is limited to 100 characters.');
    }
    if (priority == PushoverPriority.emergency) {
      if (ttl != null) {
        throw ArgumentError('Pushover emergency messages do not use ttl.');
      }
      if (!_positiveWholeSeconds(retryEvery) || retryEvery!.inSeconds < 30) {
        throw ArgumentError(
            'Pushover emergency retryEvery must be at least 30 whole seconds.');
      }
      if (!_positiveWholeSeconds(expireAfter) ||
          expireAfter!.inSeconds > 10800) {
        throw ArgumentError(
            'Pushover emergency expireAfter must be 1 to 10800 whole seconds.');
      }
      if (acknowledgementCallback case final callback?) {
        validateHttpsEndpoint(callback);
      }
    } else {
      if (retryEvery != null ||
          expireAfter != null ||
          acknowledgementCallback != null) {
        throw ArgumentError(
            'Pushover acknowledgement options require emergency priority.');
      }
      if (ttl != null && !_positiveWholeSeconds(ttl)) {
        throw ArgumentError(
            'Pushover ttl must be a positive number of whole seconds.');
      }
    }
  }

  final PushoverPriority? priority;
  final bool html;
  final String? sound;
  final Uri? url;
  final String? urlTitle;
  final Duration? ttl;
  final Duration? retryEvery;
  final Duration? expireAfter;
  final Uri? acknowledgementCallback;

  static bool _positiveWholeSeconds(Duration? duration) =>
      duration != null &&
      duration > Duration.zero &&
      duration.inMicroseconds % Duration.microsecondsPerSecond == 0;
}
