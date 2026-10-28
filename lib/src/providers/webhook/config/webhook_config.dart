import '../enums/webhook_method.dart';
import '../typedefs/webhook_payload_builder.dart';
import '../utils/normalize_webhook_headers.dart';

final class WebhookConfig {
  WebhookConfig({
    Map<String, String> headers = const {},
    this.method = WebhookMethod.post,
    this.timeout = const Duration(seconds: 15),
    this.payloadBuilder,
    String? idempotencyHeader,
  })  : headers = normalizeWebhookHeaders(headers),
        idempotencyHeader = idempotencyHeader?.toLowerCase() {
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    if (this.idempotencyHeader != null) {
      normalizeWebhookHeaders({this.idempotencyHeader!: 'validation'});
      if (const {'authorization', 'proxy-authorization', 'cookie', 'x-api-key'}
          .contains(this.idempotencyHeader)) {
        throw ArgumentError(
            'Idempotency must not overwrite authentication headers.');
      }
    }
  }

  final Map<String, String> headers;
  final WebhookMethod method;
  final Duration timeout;
  final WebhookPayloadBuilder? payloadBuilder;

  /// Set only when the receiver guarantees deduplication using this header.
  /// Enables retry of ambiguous failures as well as temporary rejections.
  final String? idempotencyHeader;
}
