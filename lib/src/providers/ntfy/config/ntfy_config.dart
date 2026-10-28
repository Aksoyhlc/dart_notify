import '../../../shared/utils/validate_https_endpoint.dart';

final class NtfyConfig {
  NtfyConfig({
    Uri? baseUrl,
    this.authToken,
    this.timeout = const Duration(seconds: 15),
  }) : baseUrl = baseUrl ?? Uri.parse('https://ntfy.sh') {
    validateHttpsEndpoint(this.baseUrl);
    if (this.baseUrl.path.isNotEmpty && this.baseUrl.path != '/') {
      throw ArgumentError(
          'Ntfy baseUrl must not contain a path; use NtfyTarget for the topic.');
    }
    if (authToken != null &&
        (authToken!.trim().isEmpty ||
            authToken!.contains('\r') ||
            authToken!.contains('\n'))) {
      throw ArgumentError('Ntfy authToken is invalid.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  final Uri baseUrl;
  final String? authToken;
  final Duration timeout;
}
