import '../delivery/delivery_context.dart';
import '../notification/notification_options.dart';
import '../notification/notify_message.dart';
import '../provider/provider_response.dart';

/// One validated provider/target pair, ready for the dispatcher to deliver.
abstract interface class DeliveryDestination {
  String get id;
  String get providerId;
  bool get supportsSafeRetry;
  bool get supportsAttachments;

  void validateOptions(NotificationOptions? options);

  Future<ProviderResponse> deliver(
    NotifyMessage message,
    DeliveryContext context, {
    NotificationOptions? options,
  });
}
