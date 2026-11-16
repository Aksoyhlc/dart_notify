/// Text substituted into an approved WhatsApp template.
final class WhatsAppTemplateParameter {
  WhatsAppTemplateParameter.positional(this.text) : name = null {
    _validateText(text);
  }

  WhatsAppTemplateParameter.named(String name, this.text) : name = name {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(name)) {
      throw ArgumentError('WhatsApp template parameter name is invalid.');
    }
    _validateText(text);
  }

  final String? name;
  final String text;

  static void _validateText(String text) {
    if (text.trim().isEmpty) {
      throw ArgumentError(
          'WhatsApp template parameter text must not be blank.');
    }
  }
}
