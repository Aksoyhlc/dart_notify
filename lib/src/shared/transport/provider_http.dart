import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/provider/provider_response.dart';
import '../utils/parse_retry_after.dart';

Future<http.Response> sendProviderRequest(
  String provider,
  Future<http.Response> Function() send,
) async {
  try {
    return await send();
  } on TimeoutException {
    throw _transportError(provider, 'timeout', 'Request timed out.');
  } on http.ClientException {
    throw _transportError(provider, 'network_error', 'Connection failed.');
  } on IOException {
    throw _transportError(provider, 'network_error', 'Connection failed.');
  }
}

Map<String, dynamic>? readProviderJson(http.Response response) {
  try {
    final result = jsonDecode(utf8.decode(response.bodyBytes));
    return result is Map<String, dynamic> ? result : null;
  } on FormatException {
    return null;
  }
}

bool isSuccessfulHttp(int status) => status >= 200 && status < 300;

bool isAmbiguousHttp(int status) => status == 408 || status >= 500;

ProviderResponse providerFailure(
  String code,
  String message, {
  http.Response? response,
  String? messageId,
  bool unknown = false,
  bool retryable = false,
}) =>
    ProviderResponse(
      status: unknown ? DeliveryStatus.unknown : DeliveryStatus.failed,
      messageId: messageId,
      retryAfter:
          retryable ? parseRetryAfter(response?.headers['retry-after']) : null,
      error: DeliveryError(
        code: code,
        message: message,
        httpStatus: response?.statusCode,
        retryable: retryable,
      ),
    );

ProviderResponse invalidProviderResponse(
  String provider,
  http.Response response,
) =>
    providerFailure(
      '${provider}_invalid_response',
      'The provider returned an unexpected success response.',
      response: response,
      unknown: true,
    );

ProviderResponse providerHttpFailure(String provider, http.Response response) {
  final status = response.statusCode;
  final ambiguous = isAmbiguousHttp(status);
  return providerFailure(
    '${provider}_http_$status',
    ambiguous
        ? 'The provider returned HTTP $status; acceptance is unknown.'
        : 'The provider rejected the request with HTTP $status.',
    response: response,
    unknown: ambiguous,
    retryable: ambiguous || status == 429,
  );
}

NotifyDeliveryException _transportError(
  String provider,
  String code,
  String message,
) =>
    NotifyDeliveryException(
      status: DeliveryStatus.unknown,
      error: DeliveryError(
        code: '${provider}_$code',
        message: message,
        retryable: true,
      ),
    );
