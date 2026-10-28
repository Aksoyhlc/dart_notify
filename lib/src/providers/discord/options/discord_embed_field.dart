final class DiscordEmbedField {
  DiscordEmbedField({
    required this.name,
    required this.value,
    this.inline = false,
  }) {
    if (name.trim().isEmpty || name.length > 256) {
      throw ArgumentError('Discord embed field name must be 1-256 characters.');
    }
    if (value.trim().isEmpty || value.length > 1024) {
      throw ArgumentError(
          'Discord embed field value must be 1-1024 characters.');
    }
  }

  final String name;
  final String value;
  final bool inline;

  Map<String, Object?> toJson() => {
        'name': name,
        'value': value,
        'inline': inline,
      };
}
