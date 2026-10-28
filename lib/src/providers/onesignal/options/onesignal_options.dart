import '../../../core/notification/notification_options.dart';

/// OneSignal-only per-send options. They stay out of the core message because
/// SMTP and other providers have no use for them.
final class OneSignalOptions implements NotificationOptions {
  OneSignalOptions({
    this.language = 'en',
    Map<String, String> localizedTitles = const {},
    Map<String, String> localizedBodies = const {},
    this.bigPicture,
    this.webImage,
    this.androidChannelId,
    this.url,
    this.appUrl,
    this.webUrl,
    this.collapseId,
    this.ttl,
    this.sendAfter,
  })  : localizedTitles = Map.unmodifiable(localizedTitles),
        localizedBodies = Map.unmodifiable(localizedBodies) {
    if (language.trim().isEmpty) throw ArgumentError('language required');
    if (ttl != null && (ttl!.inSeconds < 0 || ttl!.inSeconds > 2419200)) {
      throw ArgumentError('ttl must be between 0 and 28 days');
    }
    if (url != null && url!.scheme != 'https') {
      throw ArgumentError('url must use HTTPS');
    }
    if (webUrl != null && webUrl!.scheme != 'https') {
      throw ArgumentError('webUrl must use HTTPS');
    }
  }

  final String language;
  final Map<String, String> localizedTitles;
  final Map<String, String> localizedBodies;
  final Uri? bigPicture;
  final Uri? webImage;
  final String? androidChannelId;
  final Uri? url;
  final Uri? appUrl;
  final Uri? webUrl;
  final String? collapseId;
  final Duration? ttl;
  final DateTime? sendAfter;

  Map<String, Object?> toJson() => {
        if (bigPicture != null) 'big_picture': bigPicture.toString(),
        if (webImage != null) 'chrome_web_image': webImage.toString(),
        if (androidChannelId != null) 'android_channel_id': androidChannelId,
        if (url != null) 'url': url.toString(),
        if (appUrl != null) 'app_url': appUrl.toString(),
        if (webUrl != null) 'web_url': webUrl.toString(),
        if (collapseId != null) 'collapse_id': collapseId,
        if (ttl != null) 'ttl': ttl!.inSeconds,
        if (sendAfter != null)
          'send_after': sendAfter!.toUtc().toIso8601String(),
      };
}
