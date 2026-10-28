import '../../../core/notification/notification_target.dart';
import '../../../shared/utils/validate_https_endpoint.dart';

final class WebhookTarget implements NotificationTarget {
  WebhookTarget(this.endpoint) {
    validateHttpsEndpoint(endpoint);
  }

  final Uri endpoint;
}
