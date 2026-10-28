import 'dart:async';
import 'dart:convert';
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
import 'config/netgsm_config.dart';
import 'options/netgsm_options.dart';
import 'targets/netgsm_target.dart';

/// Standard SMS submission through Netgsm REST v2. Call close() when finished.
final class NetgsmProvider
    extends NotificationProvider<NetgsmTarget, NetgsmOptions> {
  NetgsmProvider({required this.id, required this.config, http.Client? client})
      : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
  }

  @override
  final String id;
  final NetgsmConfig config;
  final JsonHttpTransport _transport;

  /// referansID is tracking metadata, not a documented deduplication guarantee.
  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required NetgsmTarget target,
    required DeliveryContext context,
    NetgsmOptions? options,
  }) async {
    if (message.body.trim().isEmpty) {
      return const ProviderResponse(
          status: DeliveryStatus.failed,
          error: DeliveryError(
              code: 'netgsm_invalid_body',
              message: 'SMS requires a non-empty text body.'));
    }
    final payload = <String, Object?>{
      'msgheader': config.sender,
      'messages': [
        for (final number in target.numbers) {'msg': message.body, 'no': number}
      ],
      ...(options ?? NetgsmOptions()).toJson(),
      if (config.appName != null) 'appname': config.appName,
      if (config.partnerCode != null) 'partnercode': config.partnerCode,
    };
    final response = await _submit(payload);
    return _readResponse(response);
  }

  Future<http.Response> _submit(Map<String, Object?> payload) async {
    try {
      return await _transport.send(
          endpoint: config.endpoint,
          payload: payload,
          timeout: config.timeout,
          headers: {
            'authorization':
                'Basic ${base64Encode(utf8.encode('${config.username}:${config.password}'))}',
          });
    } on TimeoutException {
      throw const NotifyDeliveryException(
          status: DeliveryStatus.unknown,
          error: DeliveryError(
              code: 'netgsm_timeout',
              message: 'Netgsm request timed out; acceptance is unknown.'));
    } on http.ClientException {
      throw const NotifyDeliveryException(
          status: DeliveryStatus.unknown,
          error: DeliveryError(
              code: 'netgsm_network_error',
              message: 'Netgsm connection failed; acceptance is unknown.'));
    } on SocketException {
      throw const NotifyDeliveryException(
          status: DeliveryStatus.unknown,
          error: DeliveryError(
              code: 'netgsm_network_error',
              message: 'Netgsm connection failed; acceptance is unknown.'));
    }
  }

  ProviderResponse _readResponse(http.Response response) {
    final status = response.statusCode;
    final isSuccess = status >= 200 && status < 300;
    if (!isSuccess && status != 406) return _httpFailure(status);
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return isSuccess ? _invalidResponse() : _httpFailure(status);
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['code'] is! String ||
        !RegExp(r'^[0-9]{2,3}$').hasMatch(decoded['code'] as String)) {
      return isSuccess ? _invalidResponse() : _httpFailure(status);
    }
    final code = decoded['code'] as String;
    if (!const {'00', '01', '02'}.contains(code)) {
      return ProviderResponse(
          status: DeliveryStatus.failed,
          error: DeliveryError(
              code: 'netgsm_$code',
              httpStatus: status,
              message: 'Netgsm rejected the SMS request (code $code).'));
    }
    if (!isSuccess) return _httpFailure(status);
    final jobId = decoded['jobid'];
    if (jobId is! String || jobId.trim().isEmpty) return _invalidResponse();
    return ProviderResponse(
        status: DeliveryStatus.accepted,
        messageId: jobId,
        error: code == '00'
            ? null
            : DeliveryError(
                code: 'netgsm_$code',
                message:
                    'Netgsm accepted the SMS after adjusting the requested schedule.'));
  }

  ProviderResponse _httpFailure(int status) => ProviderResponse(
        status: status >= 500 || status == 408
            ? DeliveryStatus.unknown
            : DeliveryStatus.failed,
        error: DeliveryError(
            code: 'netgsm_http_$status',
            message: 'Netgsm returned HTTP $status.',
            httpStatus: status),
      );

  ProviderResponse _invalidResponse() => const ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
            code: 'netgsm_invalid_response',
            message: 'Netgsm returned an unexpected SMS response.'),
      );
}
