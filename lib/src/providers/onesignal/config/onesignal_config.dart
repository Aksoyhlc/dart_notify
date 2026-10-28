final class OneSignalConfig {
  OneSignalConfig({
    required this.appId,
    required this.apiKey,
    this.timeout = const Duration(seconds: 15),
    Uri? endpoint,
  }) : endpoint = endpoint ??
            Uri.parse('https://api.onesignal.com/notifications?c=push') {
    if (appId.trim().isEmpty || apiKey.trim().isEmpty) {
      throw ArgumentError('OneSignal appId and apiKey must not be empty.');
    }
    if (this.endpoint.scheme != 'https') {
      throw ArgumentError('OneSignal endpoint must use HTTPS.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final String appId;
  final String apiKey;
  final Duration timeout;
  final Uri endpoint;
}
