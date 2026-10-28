import '../../../core/notification/notification_target.dart';

final class DiscordTarget implements NotificationTarget {
  DiscordTarget({required this.webhookUrl}) {
    final url = webhookUrl;
    final host = url.host.toLowerCase();
    const allowedHosts = {
      'discord.com',
      'discordapp.com',
      'ptb.discord.com',
      'ptb.discordapp.com',
      'canary.discord.com',
      'canary.discordapp.com',
    };
    if (url.scheme != 'https' ||
        !url.hasAuthority ||
        !allowedHosts.contains(host) ||
        (url.hasPort && url.port != 443) ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !url.path.startsWith('/api/webhooks/')) {
      throw ArgumentError(
          'DiscordTarget must be an HTTPS Discord webhook URL.');
    }
  }

  final Uri webhookUrl;
}
