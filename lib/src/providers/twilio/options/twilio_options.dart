import '../../../core/notification/notification_options.dart';
import '../../../shared/utils/validate_https_endpoint.dart';

final class TwilioOptions implements NotificationOptions {
  TwilioOptions({this.statusCallback}) {
    final url = statusCallback;
    if (url != null) {
      validateHttpsEndpoint(url);
      if (url.host.contains('_')) {
        throw ArgumentError('Twilio status callback hostname is invalid.');
      }
    }
  }

  final Uri? statusCallback;
}
