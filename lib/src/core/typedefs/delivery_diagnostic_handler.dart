import '../delivery/diagnostics/delivery_diagnostic.dart';

/// A synchronous observer. Observer failures are isolated from delivery.
typedef DeliveryDiagnosticHandler = void Function(
    DeliveryDiagnostic diagnostic);
