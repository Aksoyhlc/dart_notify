import '../../../core/notification/notification_options.dart';
import 'whatsapp_template_parameter.dart';

final class WhatsAppOptions implements NotificationOptions {
  /// Use free-form text during the customer service window.
  const WhatsAppOptions.text({this.previewUrl = false})
      : templateName = null,
        languageCode = null,
        headerParameters = const [],
        bodyParameters = const [];

  /// Use a template approved for the specified language.
  WhatsAppOptions.template({
    required String name,
    required String languageCode,
    WhatsAppTemplateParameter? headerParameter,
    Iterable<WhatsAppTemplateParameter> bodyParameters = const [],
  })  : templateName = name,
        languageCode = languageCode,
        previewUrl = false,
        headerParameters = headerParameter == null
            ? const []
            : List.unmodifiable([headerParameter]),
        bodyParameters = List.unmodifiable(bodyParameters) {
    if (!RegExp(r'^[a-z0-9_]{1,512}$').hasMatch(name)) {
      throw ArgumentError('WhatsApp template name is invalid.');
    }
    if (!RegExp(r'^[a-z]{2,3}(?:_[A-Za-z0-9]+)?$').hasMatch(languageCode)) {
      throw ArgumentError('WhatsApp template language code is invalid.');
    }
    final parameters = [...headerParameters, ...this.bodyParameters];
    final hasNamed = parameters.any((parameter) => parameter.name != null);
    if (hasNamed && parameters.any((parameter) => parameter.name == null)) {
      throw ArgumentError(
          'WhatsApp template parameters must all use the same format.');
    }
    if (hasNamed &&
        this.bodyParameters.map((parameter) => parameter.name).toSet().length !=
            this.bodyParameters.length) {
      throw ArgumentError('WhatsApp body parameter names must be unique.');
    }
  }

  final bool previewUrl;
  final String? templateName;
  final String? languageCode;
  final List<WhatsAppTemplateParameter> headerParameters;
  final List<WhatsAppTemplateParameter> bodyParameters;
}
