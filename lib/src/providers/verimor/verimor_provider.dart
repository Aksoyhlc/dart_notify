import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import 'config/verimor_config.dart';
import 'options/verimor_options.dart';
import 'targets/verimor_target.dart';

/// Verimor SMS API v2 adapter. Call close() when finished.
final class VerimorProvider
    extends NotificationProvider<VerimorTarget, VerimorOptions> {
  VerimorProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final VerimorConfig config;
  final JsonHttpTransport _transport;

  static const _knownErrorCodes = <String>{
    'INVALID_SOURCE_ADDRESS',
    'MISSING_MESSAGE',
    'MESSAGE_TOO_LONG',
    'INVALID_PERIOD',
    'INVALID_DELIVERY_TIME',
    'INVALID_DATACODING',
    'MISSING_IYS_BRAND_CODE',
    'AHS_AUTHORIZATION_ERROR',
    'NO_AHS_BRAND_ERROR',
    'COMMERCIAL_SENDING_ERROR_UNDER_150K',
    'INVALID_IYS_RECIPIENT_TYPE',
    'MISSING_DESTINATION_ADDRESS',
    'INVALID_DESTINATION_ADDRESS',
    'INVALID_UTF8',
    'MUKERRER_RAPORLAMA',
    'INSUFFICIENT_CREDITS',
    'FORBIDDEN_MESSAGE',
    'INVALID_CONSENT_DATE',
    'MISSING_CONSENT',
    'MISSING_CONSENT_DATE',
    'INVALID_RECIPIENT',
    'INVALID_JSON',
    'MESSAGE_COUNT_LIMIT_EXCEEDED',
    'CUSTOM_ID_TOO_LONG_50',
    'NUMERIC_SOURCE_ADDRESS_NOT_ALLOWED',
  };

  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required VerimorTarget target,
    required DeliveryContext context,
    VerimorOptions? options,
  }) async {
    final settings = options ?? VerimorOptions();
    if (message.body.trim().isEmpty) {
      return _failure('verimor_invalid_body',
          'Verimor requires a non-empty SMS text body.');
    }
    final payload = <String, Object?>{
      'username': config.username,
      'password': config.password,
      'source_addr': config.sourceAddr,
      'datacoding': settings.datacoding.value,
      'valid_for': _formatValidFor(settings.validFor),
      if (settings.sendAt != null) 'send_at': _formatDate(settings.sendAt!),
      if (settings.customId != null) 'custom_id': settings.customId,
      if (settings.commercial) 'is_commercial': true,
      if (settings.iysRecipientType != null)
        'iys_recipient_type': settings.iysRecipientType!.wireValue,
      'messages': [
        for (final number in target.numbers)
          {'msg': message.body, 'dest': number},
      ],
    };
    final http.Response response;
    try {
      response = await _transport.send(
        endpoint: config.endpoint,
        payload: payload,
        timeout: config.timeout,
      );
    } on TimeoutException {
      throw _transportFailure('verimor_timeout', 'Verimor request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'verimor_network_error', 'Verimor connection failed');
    } on SocketException {
      throw _transportFailure(
          'verimor_network_error', 'Verimor connection failed');
    }
    return _readResponse(response);
  }

  String _formatValidFor(Duration duration) {
    final minutes = duration.inMinutes;
    final hours = (minutes ~/ 60).toString().padLeft(2, '0');
    final rest = (minutes % 60).toString().padLeft(2, '0');
    return '$hours:$rest';
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}-${two(value.month)}-${two(value.day)}'
        'T${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  NotifyDeliveryException _transportFailure(String code, String message) =>
      NotifyDeliveryException(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: code,
          message: '$message; acceptance is unknown.',
          retryable: true,
        ),
      );

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    final body = response.body.trim();
    if (status >= 200 && status < 300) {
      if (RegExp(r'^[0-9]+$').hasMatch(body)) {
        return ProviderResponse(
          status: DeliveryStatus.accepted,
          messageId: body,
        );
      }
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'verimor_invalid_success_response',
          message: 'Verimor returned an unexpected success response.',
          httpStatus: status,
        ),
      );
    }
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
        error: DeliveryError(
          code: 'verimor_429',
          message: 'Verimor rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status == 401) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'verimor_unauthorized',
          message: 'Verimor rejected the API credentials.',
          httpStatus: status,
        ),
      );
    }
    if (status == 403) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'verimor_ip_not_allowed',
          message: 'Verimor rejected the server IP address.',
          httpStatus: status,
        ),
      );
    }
    if (status >= 500 || status == 408) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'verimor_http_$status',
          message: 'Verimor returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status == 400) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'verimor_${_knownErrorCode(body)}',
          message: 'Verimor rejected the SMS request.',
          httpStatus: status,
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'verimor_http_$status',
        message: 'Verimor returned HTTP $status.',
        httpStatus: status,
      ),
    );
  }

  String _knownErrorCode(String value) {
    final candidate = value.trim().toUpperCase();
    return _knownErrorCodes.contains(candidate)
        ? candidate.toLowerCase()
        : 'unknown_error';
  }

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
