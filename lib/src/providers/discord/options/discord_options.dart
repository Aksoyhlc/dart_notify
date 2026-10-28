import '../../../core/notification/notification_options.dart';
import 'discord_embed.dart';

final class DiscordOptions implements NotificationOptions {
  DiscordOptions({
    Iterable<DiscordEmbed> embeds = const [],
    this.tts = false,
    this.suppressEmbeds = false,
    Iterable<String> allowedMentions = const [],
  })  : embeds = List.unmodifiable(embeds),
        allowedMentions = List.unmodifiable(allowedMentions.toSet()) {
    const valid = {'roles', 'users', 'everyone'};
    for (final mention in this.allowedMentions) {
      if (!valid.contains(mention)) {
        throw ArgumentError.value(
            mention, 'allowedMentions', 'Must be roles, users or everyone.');
      }
    }
  }

  final List<DiscordEmbed> embeds;
  final bool tts;
  final bool suppressEmbeds;

  /// Explicit mention targets; empty means no mentions are parsed.
  final List<String> allowedMentions;
}
