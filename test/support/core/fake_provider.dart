import 'package:dart_notify/dart_notify.dart';

import 'fake_target.dart';

final class FakeProvider
    extends NotificationProvider<FakeTarget, NoNotificationOptions> {
  FakeProvider({required this.id, this.retrySafe = true, this.behavior});
  @override
  final String id;
  final bool retrySafe;
  final Future<ProviderResponse> Function(DeliveryContext)? behavior;
  final calls = <DeliveryContext>[];

  @override
  bool get supportsSafeRetry => retrySafe;

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required FakeTarget target,
    required DeliveryContext context,
    NoNotificationOptions? options,
  }) async {
    calls.add(context);
    if (behavior != null) return await behavior!(context);
    return const ProviderResponse.accepted();
  }
}
