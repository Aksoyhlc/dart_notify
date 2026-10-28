Map<String, String> normalizeWebhookHeaders(Map<String, String> headers) {
  final normalized = <String, String>{};
  final token = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
  const reserved = {
    'host',
    'content-length',
    'transfer-encoding',
    'connection',
    'content-type',
    'trailer',
    'upgrade',
    'te'
  };
  for (final entry in headers.entries) {
    final name = entry.key.toLowerCase();
    if (!token.hasMatch(name) ||
        reserved.contains(name) ||
        entry.value.contains('\r') ||
        entry.value.contains('\n')) {
      throw ArgumentError(
          'Webhook headers contain an invalid or reserved field.');
    }
    if (normalized.containsKey(name)) {
      throw ArgumentError('Duplicate webhook header names.');
    }
    normalized[name] = entry.value;
  }
  return Map.unmodifiable(normalized);
}
