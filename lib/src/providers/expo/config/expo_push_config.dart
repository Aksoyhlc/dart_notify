final class ExpoPushConfig {
  const ExpoPushConfig({
    this.accessToken,
    this.timeout = const Duration(seconds: 15),
    this.endpoint,
  });

  final String? accessToken;
  final Duration timeout;

  /// Defaults to https://exp.host/--/api/v2/push/send.
  final Uri? endpoint;
}
