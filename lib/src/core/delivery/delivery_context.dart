/// Per-send identity handed to a provider.
///
/// [idempotencyKey] stays the same across retries of one destination send;
/// [attempt] starts at 1 and increments before each provider call.
final class DeliveryContext {
  const DeliveryContext({required this.idempotencyKey, required this.attempt});

  final String idempotencyKey;
  final int attempt;
}
