import '../delivery/delivery_context.dart';
import '../notification/notification_options.dart';
import '../notification/notification_target.dart';
import '../notification/notify_message.dart';
import 'provider_response.dart';

/// Provider contract. Retries require [supportsSafeRetry] to be true.
abstract base class NotificationProvider<T extends NotificationTarget,
    O extends NotificationOptions> {
  const NotificationProvider();

  String get id;

  /// True when repeating a send cannot duplicate the message.
  bool get supportsSafeRetry;

  /// Providers that can carry [NotifyMessage.attachments] override this.
  bool get supportsAttachments => false;

  /// Checks the concrete provider's target type even if callers widen generics.
  void validateTarget(NotificationTarget target) {
    if (target is! T) {
      throw ArgumentError('Target is incompatible with provider "$id".');
    }
  }

  void validateOptions(NotificationOptions? options) {
    if (options != null && options is! O) {
      throw ArgumentError('Options are incompatible with provider "$id".');
    }
  }

  Future<ProviderResponse> send({
    required NotifyMessage message,
    required T target,
    required DeliveryContext context,
    O? options,
  });
}
