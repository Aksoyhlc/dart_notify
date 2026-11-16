import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class ProviderHttpFixture {
  ProviderHttpFixture(String responseBody, {int status = 200}) {
    respond = (_) => http.Response(responseBody, status);
    client = MockClient((request) async {
      requests.add(request);
      return await respond(request);
    });
  }

  final requests = <http.Request>[];
  late final MockClient client;
  late FutureOr<http.Response> Function(http.Request) respond;
}
