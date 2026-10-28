import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'multipart_file_part.dart';

/// Multipart form transport for providers that upload local files. Owns only
/// clients it creates, never follows redirects and applies one response timeout.
final class MultipartHttpTransport {
  MultipartHttpTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<http.Response> send({
    required Uri endpoint,
    required Map<String, String> fields,
    Iterable<MultipartFilePart> files = const [],
    required Duration timeout,
    Map<String, String> headers = const {},
  }) {
    final request = http.MultipartRequest('POST', endpoint)
      ..followRedirects = false
      ..headers.addAll({'accept': 'application/json', ...headers})
      ..fields.addAll(fields);
    for (final file in files) {
      request.files.add(http.MultipartFile.fromBytes(
        file.field,
        file.bytes,
        filename: file.fileName,
        contentType: MediaType.parse(file.contentType),
      ));
    }
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
