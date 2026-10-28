import 'dart:convert';

List<int> readBase64MimePart(String mime, String contentType) {
  final part = RegExp(
    'content-type: ${RegExp.escape(contentType)}[^\\r\\n]*\\r\\n'
    r'(?:[^\r\n]+\r\n)*\r\n([A-Za-z0-9+/=\r\n]+)',
    caseSensitive: false,
  ).firstMatch(mime);
  if (part == null) throw StateError('Missing MIME part: $contentType');
  return base64.decode(part.group(1)!.replaceAll(RegExp(r'\s'), ''));
}
