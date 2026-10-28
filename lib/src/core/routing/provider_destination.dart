import '../delivery/delivery_context.dart';
import '../notification/notification_options.dart';
import '../notification/notification_target.dart';
import '../notification/notify_message.dart';
import '../provider/notification_provider.dart';
import '../provider/provider_response.dart';
import 'delivery_destination.dart';

final class ProviderDestination<T extends NotificationTarget,
    O extends NotificationOptions> implements DeliveryDestination {
  ProviderDestination({
    required this.id,
    required this.provider,
    required this.target,
    this.options,
  }) {
    if (id.trim().isEmpty) throw ArgumentError('Destination ID is required.');
    if (provider.id.trim().isEmpty) {
      throw ArgumentError('Provider ID is required.');
    }
    provider.validateTarget(target);
    provider.validateOptions(options);
  }

  @override
  final String id;
  final NotificationProvider<T, O> provider;
  final T target;
  final O? options;

  @override
  String get providerId => provider.id;

  @override
  bool get supportsSafeRetry => provider.supportsSafeRetry;

  @override
  bool get supportsAttachments => provider.supportsAttachments;

  @override
  void validateOptions(NotificationOptions? options) =>
      provider.validateOptions(options);

  @override
  Future<ProviderResponse> deliver(
    NotifyMessage message,
    DeliveryContext context, {
    NotificationOptions? options,
  }) {
    final effectiveOptions = options ?? this.options;
    validateOptions(effectiveOptions);
    return provider.send(
      message: message,
      target: target,
      context: context,
      options: effectiveOptions as O?,
    );
  }
}
