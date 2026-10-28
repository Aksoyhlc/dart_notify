import 'dart:convert';

import 'package:http/http.dart' as http;

/// Owns only clients it creates. Redirects never forward notification secrets.
final class JsonHttpTransport {
  JsonHttpTransport({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  Future<http.Response> send({
    required Uri endpoint,
    required Object? payload,
    required Duration timeout,
    String method = 'POST',
    Map<String, String> headers = const {},
  }) {
    final request = http.Request(method, endpoint)
      ..followRedirects = false
      ..headers.addAll({
        'accept': 'application/json',
        ...headers,
        'content-type': 'application/json; charset=utf-8',
      })
      ..body = jsonEncode(payload);
    return _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(timeout);
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
