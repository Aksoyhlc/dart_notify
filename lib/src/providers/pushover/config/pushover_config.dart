final class PushoverConfig {
  PushoverConfig({
    required this.appToken,
    this.timeout = const Duration(seconds: 15),
  }) {
    if (!RegExp(r'^[A-Za-z0-9]{30}$').hasMatch(appToken)) {
      throw ArgumentError('Pushover appToken must be a 30-character token.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final String appToken;
  final Duration timeout;
}
