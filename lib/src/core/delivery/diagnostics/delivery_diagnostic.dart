/// Original failure details for trusted, application-owned diagnostics only.
/// [error] and [stackTrace] may contain credentials or recipient information.
final class DeliveryDiagnostic {
  const DeliveryDiagnostic({
    required this.destinationId,
    required this.providerId,
    required this.attempt,
    required this.error,
    required this.stackTrace,
  });

  final String destinationId;
  final String providerId;
  final int attempt;
  final Object error;
  final StackTrace stackTrace;
}
