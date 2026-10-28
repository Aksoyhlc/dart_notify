import 'dart:convert';

import 'package:http/http.dart' as http;

final class RecordingHttpClient extends http.BaseClient {
  RecordingHttpClient(this.responseBody);

  final String responseBody;
  bool isClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (isClosed) throw StateError('Client is closed.');
    await request.finalize().drain<void>();
    return http.StreamedResponse(Stream.value(utf8.encode(responseBody)), 200);
  }

  @override
  void close() => isClosed = true;
}
