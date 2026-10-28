import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/delivery/errors/notify_delivery_exception.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/notification/notification_options.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import 'config/iletimerkezi_config.dart';
import 'enums/iletimerkezi_iys.dart';
import 'options/iletimerkezi_options.dart';
import 'targets/iletimerkezi_target.dart';

/// İletimerkezi REST v1 SMS adapter. Call close() when finished.
final class IletimerkeziProvider
    extends NotificationProvider<IletimerkeziTarget, IletimerkeziOptions> {
  IletimerkeziProvider({
    required this.id,
    required this.config,
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final IletimerkeziConfig config;
  final JsonHttpTransport _transport;

  @override
  bool get supportsSafeRetry => false;

  @override
  void validateOptions(NotificationOptions? options) {
    super.validateOptions(options);
    if (config.sender == 'APITEST' &&
        options is IletimerkeziOptions &&
        options.iys != IletimerkeziIys.transactional) {
      throw ArgumentError(
          'İletimerkezi APITEST sender requires transactional IYS.');
    }
  }

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required IletimerkeziTarget target,
    required DeliveryContext context,
    IletimerkeziOptions? options,
  }) async {
    final settings = options ?? IletimerkeziOptions();
    if (message.body.trim().isEmpty) {
      return _failure('iletimerkezi_invalid_body',
          'İletimerkezi requires a non-empty SMS text body.');
    }
    final payload = <String, Object?>{
      'request': {
        'authentication': {'key': config.key, 'hash': config.hash},
        'order': {
          'sender': config.sender,
          'iys': settings.iys.wireValue,
          if (settings.iys.recipientType != null)
            'iysList': settings.iys.recipientType,
          if (settings.sendAt != null)
            'sendDateTime': _formatDate(settings.sendAt!),
          'message': {
            'text': message.body,
            'receipents': {'number': target.numbers},
          },
        },
      },
    };
    final http.Response response;
    try {
      response = await _transport.send(
        endpoint: config.endpoint,
        payload: payload,
        timeout: config.timeout,
      );
    } on TimeoutException {
      throw _transportFailure(
          'iletimerkezi_timeout', 'İletimerkezi request timed out');
    } on http.ClientException {
      throw _transportFailure(
          'iletimerkezi_network_error', 'İletimerkezi connection failed');
    } on SocketException {
      throw _transportFailure(
          'iletimerkezi_network_error', 'İletimerkezi connection failed');
    }
    return _readResponse(response);
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year.toString().padLeft(4, '0')}'
        ' ${two(value.hour)}:${two(value.minute)}';
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
    if (status < 200 || status >= 300) return _httpFailure(response);
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return _unexpected();
    }
    if (decoded is! Map) return _unexpected();
    final envelope = decoded['response'];
    if (envelope is! Map) return _unexpected();
    final statusBlock = envelope['status'];
    final code = statusBlock is Map ? statusBlock['code'] : null;
    if (code is! int) return _unexpected();
    if (code != 200) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: 'iletimerkezi_$code',
          message: 'İletimerkezi rejected the SMS request (code $code).',
          httpStatus: status,
        ),
      );
    }
    final order = envelope['order'];
    final orderId = order is Map ? order['id'] : null;
    if (orderId == null || orderId.toString().trim().isEmpty) {
      return _unexpected();
    }
    return ProviderResponse(
      status: DeliveryStatus.accepted,
      messageId: orderId.toString(),
    );
  }

  ProviderResponse _httpFailure(http.Response response) {
    final status = response.statusCode;
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: parseRetryAfter(response.headers['retry-after']),
        error: DeliveryError(
          code: 'iletimerkezi_429',
          message: 'İletimerkezi rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500 || status == 408) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'iletimerkezi_http_$status',
          message: 'İletimerkezi returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'iletimerkezi_http_$status',
        message: 'İletimerkezi returned HTTP $status.',
        httpStatus: status,
      ),
    );
  }

  ProviderResponse _unexpected() => const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'iletimerkezi_invalid_response',
          message: 'İletimerkezi returned an unexpected SMS response.',
        ),
      );

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );
}
