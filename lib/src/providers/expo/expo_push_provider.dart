import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/delivery/delivery_context.dart';
import '../../core/delivery/errors/delivery_error.dart';
import '../../core/enums/delivery_status.dart';
import '../../core/notification/notify_message.dart';
import '../../core/provider/notification_provider.dart';
import '../../core/provider/provider_response.dart';
import '../../shared/transport/json_http_transport.dart';
import '../../shared/utils/parse_retry_after.dart';
import '../../shared/utils/validate_https_endpoint.dart';
import 'config/expo_push_config.dart';
import 'enums/expo_priority.dart';
import 'options/expo_push_options.dart';
import 'targets/expo_push_target.dart';

/// Expo Push Service adapter. Call close() when finished.
final class ExpoPushProvider
    extends NotificationProvider<ExpoPushTarget, ExpoPushOptions> {
  ExpoPushProvider({
    required this.id,
    this.config = const ExpoPushConfig(),
    http.Client? client,
  }) : _transport = JsonHttpTransport(client: client) {
    if (id.trim().isEmpty) throw ArgumentError('Provider ID is required.');
    if (config.timeout <= Duration.zero) {
      throw ArgumentError('timeout must be positive.');
    }
    if (config.accessToken != null &&
        (config.accessToken!.trim().isEmpty ||
            config.accessToken!.contains('\r') ||
            config.accessToken!.contains('\n'))) {
      throw ArgumentError('Expo access token is invalid.');
    }
    validateHttpsEndpoint(_endpoint);
  }

  @override
  final String id;
  final ExpoPushConfig config;
  final JsonHttpTransport _transport;

  static const int _maxBatch = 100;

  Uri get _endpoint =>
      config.endpoint ?? Uri.parse('https://exp.host/--/api/v2/push/send');

  @override
  bool get supportsSafeRetry => false;

  void close() => _transport.close();

  @override
  Future<ProviderResponse> send({
    required NotifyMessage message,
    required ExpoPushTarget target,
    required DeliveryContext context,
    ExpoPushOptions? options,
  }) async {
    final settings = options ?? ExpoPushOptions();
    if (!_isJsonSerializable(settings.data)) {
      return _failure(
          'expo_invalid_data', 'Expo data must be JSON-serializable.');
    }
    final templates = _message(message, settings);
    final accepted = <int, String>{};
    final ticketErrors = <int, String>{};
    ProviderResponse? terminal;
    int? terminalFrom;
    for (var start = 0; start < target.tokens.length; start += _maxBatch) {
      final end = (start + _maxBatch) > target.tokens.length
          ? target.tokens.length
          : start + _maxBatch;
      final batch = [
        for (final token in target.tokens.sublist(start, end))
          {...templates, 'to': token},
      ];
      final http.Response response;
      try {
        response = await _transport.send(
          endpoint: _endpoint,
          payload: batch,
          timeout: config.timeout,
          headers: {
            if (config.accessToken != null)
              'authorization': 'Bearer ${config.accessToken}',
          },
        );
      } on TimeoutException {
        terminal = _transportResponse('expo_timeout', 'Expo request timed out');
        terminalFrom = start;
        break;
      } on http.ClientException {
        terminal =
            _transportResponse('expo_network_error', 'Expo connection failed');
        terminalFrom = start;
        break;
      } on SocketException {
        terminal =
            _transportResponse('expo_network_error', 'Expo connection failed');
        terminalFrom = start;
        break;
      }
      final chunk = _readChunk(response, start, batch.length);
      accepted.addAll(chunk.accepted);
      ticketErrors.addAll(chunk.errors);
      terminal = chunk.terminal;
      terminalFrom = chunk.unresolvedFrom;
      if (terminal != null) break;
    }
    return _aggregate(
      target: target,
      accepted: accepted,
      ticketErrors: ticketErrors,
      terminal: terminal,
      terminalFrom: terminalFrom,
    );
  }

  Map<String, Object?> _message(
    NotifyMessage message,
    ExpoPushOptions options,
  ) {
    final body =
        message.body.trim().isEmpty ? (message.htmlBody ?? '') : message.body;
    return {
      if (message.title != null) 'title': message.title,
      'body': body,
      if (options.sound != null) 'sound': options.sound,
      if (options.badge != null) 'badge': options.badge,
      if (options.channelId != null) 'channelId': options.channelId,
      if (options.categoryId != null) 'categoryId': options.categoryId,
      if (options.ttl != null) 'ttl': options.ttl!.inSeconds,
      if (options.expiration != null)
        'expiration': options.expiration!.millisecondsSinceEpoch ~/ 1000,
      'priority': (options.priority ?? ExpoPriority.defaultPriority).wireValue,
      if (options.subtitle != null) 'subtitle': options.subtitle,
      if (options.mutableContent != null)
        'mutableContent': options.mutableContent,
      if (options.data.isNotEmpty) 'data': options.data,
    };
  }

  ({
    Map<int, String> accepted,
    Map<int, String> errors,
    ProviderResponse? terminal,
    int? unresolvedFrom,
  }) _readChunk(
    http.Response response,
    int start,
    int length,
  ) {
    if (response.statusCode != 200) {
      return (
        accepted: <int, String>{},
        errors: <int, String>{},
        terminal: _httpFailure(response),
        unresolvedFrom: start,
      );
    }
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      return (
        accepted: <int, String>{},
        errors: <int, String>{},
        terminal: _unexpected('Expo returned a non-JSON response.'),
        unresolvedFrom: start,
      );
    }
    if (body is! Map) {
      return (
        accepted: <int, String>{},
        errors: <int, String>{},
        terminal: _unexpected('Expo returned an unexpected envelope.'),
        unresolvedFrom: start,
      );
    }
    var tickets = body['data'];
    if (tickets is Map) tickets = [tickets];
    if (tickets is! List || tickets.length != length) {
      return (
        accepted: <int, String>{},
        errors: <int, String>{},
        terminal: _unexpected('Expo returned an unexpected ticket list.'),
        unresolvedFrom: start,
      );
    }
    final accepted = <int, String>{};
    final errors = <int, String>{};
    for (var offset = 0; offset < tickets.length; offset++) {
      final ticket = tickets[offset];
      final index = start + offset;
      if (ticket is! Map) {
        return (
          accepted: accepted,
          errors: errors,
          terminal: _unexpected('Expo returned a malformed ticket.'),
          unresolvedFrom: index,
        );
      }
      if (ticket['status'] == 'ok') {
        final ticketId = ticket['id'];
        if (ticketId is! String || ticketId.isEmpty) {
          return (
            accepted: accepted,
            errors: errors,
            terminal: _unexpected('Expo returned a ticket without an ID.'),
            unresolvedFrom: index,
          );
        }
        accepted[index] = ticketId;
        continue;
      }
      if (ticket['status'] == 'error') {
        final details = ticket['details'];
        final raw = details is Map ? details['error'] : null;
        errors[index] = _normalizeError(raw);
        continue;
      }
      return (
        accepted: accepted,
        errors: errors,
        terminal: _unexpected('Expo returned an unknown ticket status.'),
        unresolvedFrom: index,
      );
    }
    return (
      accepted: accepted,
      errors: errors,
      terminal: null,
      unresolvedFrom: null,
    );
  }

  ProviderResponse _aggregate({
    required ExpoPushTarget target,
    required Map<int, String> accepted,
    required Map<int, String> ticketErrors,
    required ProviderResponse? terminal,
    required int? terminalFrom,
  }) {
    if (terminal != null) {
      if (accepted.isEmpty) {
        final detail = _describe(ticketErrors);
        return ProviderResponse(
          status: terminal.status,
          retryAfter: terminal.retryAfter,
          error: DeliveryError(
            code: terminal.error?.code ?? 'expo_invalid_response',
            message: [
              terminal.error?.message ?? 'Expo stopped the batch.',
              if (ticketErrors.isNotEmpty) 'Completed ticket errors: $detail.',
              'Uncertain or unsubmitted token indexes '
                  '${_formatIndexes(_suffixIndexes(terminalFrom, target.tokens.length))}.',
            ].join(' '),
            httpStatus: terminal.error?.httpStatus,
            retryable: terminal.error?.retryable ?? false,
          ),
        );
      }
      return ProviderResponse(
        status: DeliveryStatus.partiallyAccepted,
        retryAfter: terminal.retryAfter,
        error: DeliveryError(
          code: 'expo_partial_batch',
          message: 'Batch stopped with ${terminal.error?.code ?? 'unknown'}; '
              'accepted token indexes ${_formatIndexes(accepted.keys)}; '
              'ticket errors: ${_describe(ticketErrors)}; '
              'uncertain or unsubmitted token indexes '
              '${_formatIndexes(_suffixIndexes(terminalFrom, target.tokens.length))}.',
          httpStatus: terminal.error?.httpStatus,
        ),
      );
    }
    if (ticketErrors.isEmpty) {
      return ProviderResponse(
        status: DeliveryStatus.accepted,
        messageId: target.tokens.length == 1 ? accepted[0] : null,
      );
    }
    final codes = ticketErrors.values.toSet();
    final code =
        codes.length == 1 ? codes.single : 'expo_multiple_ticket_errors';
    final detail = _describe(ticketErrors);
    if (accepted.isEmpty) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(
          code: code,
          message: detail,
          retryable:
              codes.length == 1 && codes.single == 'expo_message_rate_exceeded',
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.partiallyAccepted,
      error: DeliveryError(code: code, message: detail),
    );
  }

  ProviderResponse _httpFailure(http.Response response) {
    final status = response.statusCode;
    final retryAfter = parseRetryAfter(response.headers['retry-after']);
    if (status == 429) {
      return ProviderResponse(
        status: DeliveryStatus.failed,
        retryAfter: retryAfter,
        error: DeliveryError(
          code: 'expo_429',
          message: 'Expo rate limited the request.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    if (status >= 500 || status == 408) {
      return ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'expo_http_$status',
          message: 'Expo returned a server error.',
          httpStatus: status,
          retryable: true,
        ),
      );
    }
    return ProviderResponse(
      status: DeliveryStatus.failed,
      error: DeliveryError(
        code: 'expo_${_upstreamError(response.body) ?? 'http_$status'}',
        message: 'Expo rejected the request.',
        httpStatus: status,
      ),
    );
  }

  String? _upstreamError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final errors = decoded['errors'];
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          final code = (errors.first as Map)['code'];
          if (code is String && code.trim().isNotEmpty) {
            return _normalizeError(code).replaceFirst('expo_', '');
          }
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  ProviderResponse _unexpected(String message) => ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: 'expo_invalid_response',
          message: message,
        ),
      );

  ProviderResponse _transportResponse(String code, String message) =>
      ProviderResponse(
        status: DeliveryStatus.unknown,
        error: DeliveryError(
          code: code,
          message: '$message; acceptance is unknown.',
          retryable: true,
        ),
      );

  ProviderResponse _failure(String code, String message) => ProviderResponse(
        status: DeliveryStatus.failed,
        error: DeliveryError(code: code, message: message),
      );

  bool _isJsonSerializable(Object? value) {
    try {
      jsonEncode(value);
      return true;
    } on JsonUnsupportedObjectError {
      return false;
    }
  }

  String _normalizeError(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return 'expo_unknown_error';
    final normalized = raw
        .replaceAllMapped(
            RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    final trimmed = normalized.replaceAll(RegExp(r'^_+|_+$'), '');
    final capped = trimmed.length > 56 ? trimmed.substring(0, 56) : trimmed;
    return 'expo_$capped';
  }

  String _describe(Map<int, String> errors) {
    final parts = [
      for (final entry in errors.entries) 'token[${entry.key}]=${entry.value}',
    ];
    final joined = parts.join(', ');
    return joined.length > 300 ? '${joined.substring(0, 297)}...' : joined;
  }

  Iterable<int> _suffixIndexes(int? start, int length) sync* {
    if (start == null) return;
    for (var index = start; index < length; index++) {
      yield index;
    }
  }

  String _formatIndexes(Iterable<int> indexes) {
    if (indexes.isEmpty) return 'none';
    final sorted = indexes.toList()..sort();
    final ranges = <String>[];
    var first = sorted.first;
    var last = first;
    for (final index in sorted.skip(1)) {
      if (index == last + 1) {
        last = index;
        continue;
      }
      ranges.add(first == last ? '$first' : '$first-$last');
      first = last = index;
    }
    ranges.add(first == last ? '$first' : '$first-$last');
    final result = ranges.join(',');
    return result.length > 180 ? '${result.substring(0, 177)}...' : result;
  }
}
