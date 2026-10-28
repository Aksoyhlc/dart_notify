import '../../../core/notification/notification_options.dart';
import '../enums/webhook_method.dart';
import '../utils/normalize_webhook_headers.dart';

final class WebhookOptions implements NotificationOptions {
  WebhookOptions({
    Map<String, String> headers = const {},
    this.method,
    Map<String, Object?>? payload,
  })  : headers = normalizeWebhookHeaders(headers),
        payload = payload == null ? null : Map.unmodifiable(payload);

  final Map<String, String> headers;
  final WebhookMethod? method;

  /// Replaces the default or builder-generated JSON body for this send.
  final Map<String, Object?>? payload;
}
