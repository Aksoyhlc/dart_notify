import '../../../shared/utils/validate_https_endpoint.dart';

final class DiscordConfig {
  DiscordConfig({
    this.username,
    this.avatarUrl,
    this.threadId,
    this.timeout = const Duration(seconds: 15),
  }) {
    if (username != null &&
        (username!.trim().isEmpty ||
            username!.contains('\r') ||
            username!.contains('\n'))) {
      throw ArgumentError('Discord username must not be blank.');
    }
    if (avatarUrl != null) validateHttpsEndpoint(avatarUrl!);
    if (threadId != null && !RegExp(r'^[0-9]{5,}$').hasMatch(threadId!)) {
      throw ArgumentError('Discord threadId must be a numeric ID.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final String? username;
  final Uri? avatarUrl;
  final String? threadId;
  final Duration timeout;
}
