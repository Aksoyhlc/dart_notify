enum TelegramParseMode {
  plain(null),
  markdownV2('MarkdownV2'),
  html('HTML');

  const TelegramParseMode(this.wireValue);

  final String? wireValue;
}
