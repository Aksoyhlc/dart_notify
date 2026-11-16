import '../../../shared/utils/is_e164_phone_number.dart';

/// Twilio SMS credentials and sender configuration.
final class TwilioConfig {
  /// Uses an API key SID and secret for production authentication.
  TwilioConfig({
    required String accountSid,
    required String apiKeySid,
    required String apiKeySecret,
    String? from,
    String? messagingServiceSid,
    Duration timeout = const Duration(seconds: 15),
  }) : this._(
          accountSid: accountSid,
          apiKeySid: apiKeySid,
          secret: apiKeySecret,
          from: from,
          messagingServiceSid: messagingServiceSid,
          timeout: timeout,
        );

  /// Uses the Account SID as the Basic auth username.
  TwilioConfig.withAuthToken({
    required String accountSid,
    required String authToken,
    String? from,
    String? messagingServiceSid,
    Duration timeout = const Duration(seconds: 15),
  }) : this._(
          accountSid: accountSid,
          secret: authToken,
          from: from,
          messagingServiceSid: messagingServiceSid,
          timeout: timeout,
        );

  TwilioConfig._({
    required this.accountSid,
    this.apiKeySid,
    required this.secret,
    required this.from,
    required this.messagingServiceSid,
    required this.timeout,
  }) {
    if (!_accountSid.hasMatch(accountSid)) {
      throw ArgumentError('Twilio accountSid is invalid.');
    }
    if (apiKeySid != null && !_apiKeySid.hasMatch(apiKeySid!)) {
      throw ArgumentError('Twilio apiKeySid is invalid.');
    }
    if (secret.isEmpty || RegExp(r'[^\x21-\x7e]').hasMatch(secret)) {
      throw ArgumentError('Twilio authentication secret is invalid.');
    }
    if (from == null && messagingServiceSid == null) {
      throw ArgumentError('Twilio requires from or messagingServiceSid.');
    }
    final sender = from;
    if (sender != null &&
        !isE164PhoneNumber(sender) &&
        !_shortCode.hasMatch(sender) &&
        !(_alphaSender.hasMatch(sender) && _letter.hasMatch(sender))) {
      throw ArgumentError('Twilio SMS sender is invalid.');
    }
    if (messagingServiceSid != null &&
        !_messagingServiceSid.hasMatch(messagingServiceSid!)) {
      throw ArgumentError('Twilio messagingServiceSid is invalid.');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
  }

  static final _accountSid = RegExp(r'^AC[0-9a-fA-F]{32}$');
  static final _apiKeySid = RegExp(r'^SK[0-9a-fA-F]{32}$');
  static final _messagingServiceSid = RegExp(r'^MG[0-9a-fA-F]{32}$');
  static final _shortCode = RegExp(r'^[0-9]{3,8}$');
  static final _alphaSender = RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ]{0,10}$');
  static final _letter = RegExp(r'[A-Za-z]');

  final String accountSid;
  final String? apiKeySid;
  final String secret;
  final String? from;
  final String? messagingServiceSid;
  final Duration timeout;
}
