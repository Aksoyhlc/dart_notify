import 'discord_embed_field.dart';

final class DiscordEmbed {
  DiscordEmbed({
    this.title,
    this.description,
    this.url,
    this.color,
    Iterable<DiscordEmbedField> fields = const [],
    this.footerText,
    this.imageUrl,
    this.timestamp,
  }) : fields = List.unmodifiable(fields) {
    if (title != null && title!.length > 256) {
      throw ArgumentError(
          'Discord embed title must not exceed 256 characters.');
    }
    if (description != null && description!.length > 4096) {
      throw ArgumentError(
          'Discord embed description must not exceed 4096 characters.');
    }
    if (this.fields.length > 25) {
      throw ArgumentError('Discord embeds support at most 25 fields.');
    }
    if (footerText != null && footerText!.length > 2048) {
      throw ArgumentError(
          'Discord embed footer must not exceed 2048 characters.');
    }
    if (color != null && (color! < 0 || color! > 0xFFFFFF)) {
      throw ArgumentError('Discord embed color must be a 24-bit RGB value.');
    }
  }

  final String? title;
  final String? description;
  final Uri? url;
  final int? color;
  final List<DiscordEmbedField> fields;
  final String? footerText;
  final Uri? imageUrl;
  final DateTime? timestamp;

  int get characterCount =>
      (title?.length ?? 0) +
      (description?.length ?? 0) +
      (footerText?.length ?? 0) +
      fields.fold<int>(
          0, (total, field) => total + field.name.length + field.value.length);

  Map<String, Object?> toJson() => {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (url != null) 'url': url.toString(),
        if (color != null) 'color': color,
        if (fields.isNotEmpty)
          'fields': [for (final field in fields) field.toJson()],
        if (footerText != null) 'footer': {'text': footerText},
        if (imageUrl != null) 'image': {'url': imageUrl.toString()},
        if (timestamp != null)
          'timestamp': timestamp!.toUtc().toIso8601String(),
      };
}
