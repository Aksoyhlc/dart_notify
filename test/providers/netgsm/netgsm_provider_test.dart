import 'dart:async';
import 'dart:convert';

import 'package:dart_notify/dart_notify.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final message = NotifyMessage(title: 'Not SMS content', body: 'Türkçe mesaj');
  NetgsmProvider provider(http.Client client) => NetgsmProvider(
        id: 'sms',
        config: NetgsmConfig(
            username: '8501234567',
            password: 'secret',
            sender: 'MYAPP',
            appName: 'dart_notify'),
        client: client,
      );
  Future<DeliveryResult> send(NetgsmProvider sms, {NetgsmOptions? options}) =>
      DartNotify(destinations: []).sendDirect(message,
          provider: sms,
          target: NetgsmTarget(
              numbers: ['5321234567', '5321234567', '+421123456789']),
          options: options);

  test('submits authenticated REST v2 SMS and preserves a long job ID',
      () async {
    late http.Request request;
    final sms = provider(MockClient((r) async {
      request = r;
      return http.Response(
          '{"code":"00","jobid":"17377215342605050417149344","description":"queued"}',
          200);
    }));
    final result = await send(sms,
        options: NetgsmOptions(
          encoding: NetgsmEncoding.turkish,
          iysFilter: NetgsmIysFilter.commercialIndividual,
          referenceId: 'order-42',
        ));
    expect(result.isFullyAccepted, isTrue);
    expect(result.messageId, '17377215342605050417149344');
    expect(
        request.url.toString(), 'https://api.netgsm.com.tr/sms/rest/v2/send');
    expect(request.method, 'POST');
    expect(request.followRedirects, isFalse);
    expect(request.headers['authorization'],
        'Basic ${base64Encode(utf8.encode('8501234567:secret'))}');
    expect(jsonDecode(request.body), {
      'msgheader': 'MYAPP',
      'messages': [
        {'msg': 'Türkçe mesaj', 'no': '5321234567'},
        {'msg': 'Türkçe mesaj', 'no': '00421123456789'},
      ],
      'encoding': 'TR',
      'iysfilter': '11',
      'appname': 'dart_notify',
      'referansID': 'order-42',
    });
  });

  test(
      'scheduled SMS uses documented calendar format without timezone conversion',
      () async {
    late Map<String, dynamic> payload;
    final sms = provider(MockClient((r) async {
      payload = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response('{"code":"00","jobid":"job"}', 200);
    }));
    await send(sms,
        options: NetgsmOptions(
          encoding: NetgsmEncoding.unicode,
          iysFilter: NetgsmIysFilter.commercialBusiness,
          startAt: DateTime.utc(2026, 11, 3, 9, 5),
          stopAt: DateTime.utc(2026, 11, 3, 21, 5),
        ));
    expect(payload['startdate'], '031120260905');
    expect(payload['stopdate'], '031120262105');
    expect(payload['encoding'], 'UNICODE');
    expect(payload['iysfilter'], '12');
  });

  for (final code in ['01', '02']) {
    test(
        'schedule adjustment $code is accepted with a warning, never resubmitted',
        () async {
      var calls = 0;
      final sms = provider(MockClient((_) async {
        calls++;
        return http.Response('{"code":"$code","jobid":"job"}', 200);
      }));
      final result = await send(sms);
      expect(result.isFullyAccepted, isTrue);
      expect(result.error?.code, 'netgsm_$code');
      expect(calls, 1);
    });
  }

  for (final status in [200, 406]) {
    for (final code in ['20', '30', '40', '50', '51', '70', '80', '85']) {
      test(
          'business rejection $code with HTTP $status is sanitized and not retried',
          () async {
        var calls = 0;
        final sms = provider(MockClient((_) async {
          calls++;
          return http.Response(
              '{"code":"$code","jobid":null,"description":"secret 5321234567"}',
              status);
        }));
        final result = await send(sms);
        expect(result.status, DeliveryStatus.failed);
        expect(result.error?.code, 'netgsm_$code');
        expect(result.error.toString(), isNot(contains('secret')));
        expect(result.error.toString(), isNot(contains('5321234567')));
        expect(calls, 1);
      });
    }
  }

  for (final body in [
    'not json',
    '[]',
    '{}',
    '{"code":0,"jobid":"job"}',
    '{"code":"00"}',
    '{"code":"00","jobid":123}',
    '{"code":"00","jobid":""}'
  ]) {
    test('ambiguous response is unknown: $body', () async {
      final result = await send(
          provider(MockClient((_) async => http.Response(body, 200))));
      expect(result.status, DeliveryStatus.unknown);
      expect(result.error?.code, 'netgsm_invalid_response');
    });
  }

  test('timeouts cannot automatically duplicate an SMS', () async {
    var calls = 0;
    final sms = provider(MockClient((_) async {
      calls++;
      throw TimeoutException('secret');
    }));
    final result = await send(sms);
    expect(result.status, DeliveryStatus.unknown);
    expect(result.error?.code, 'netgsm_timeout');
    expect(result.attempts, 1);
    expect(calls, 1);
  });

  for (final status in [302, 401, 429, 503]) {
    test('HTTP $status does not trigger unsafe retries', () async {
      final result = await send(
          provider(MockClient((_) async => http.Response('secret', status))));
      expect(result.isFullyAccepted, isFalse);
      expect(result.attempts, 1);
      expect(result.error?.code, 'netgsm_http_$status');
      expect(result.status,
          status >= 500 ? DeliveryStatus.unknown : DeliveryStatus.failed);
    });
  }

  test('invalid recipients, credentials, sender and schedule fail early', () {
    expect(() => NetgsmTarget(numbers: []), throwsArgumentError);
    expect(() => NetgsmTarget(numbers: ['not a phone']), throwsArgumentError);
    expect(
        () => NetgsmConfig(username: 'u:other', password: 'p', sender: 'APP'),
        throwsArgumentError);
    expect(() => NetgsmConfig(username: 'u', password: '', sender: 'APP'),
        throwsArgumentError);
    expect(() => NetgsmConfig(username: 'u', password: 'p', sender: 'ab'),
        throwsArgumentError);
    expect(
        () => NetgsmOptions(
            startAt: DateTime(2026, 11, 3), stopAt: DateTime(2026, 11, 2)),
        throwsArgumentError);
    expect(
        () => NetgsmConfig(
            username: 'u',
            password: 'p',
            sender: 'APP',
            endpoint: Uri.parse('http://api.example.com/send')),
        throwsArgumentError);
  });

  test('HTML-only messages are rejected before contacting Netgsm', () async {
    var calls = 0;
    final sms = provider(MockClient((_) async {
      calls++;
      return http.Response('', 200);
    }));
    final result = await DartNotify(destinations: []).sendDirect(
      NotifyMessage(body: '', htmlBody: '<b>Not SMS</b>'),
      provider: sms,
      target: NetgsmTarget(numbers: ['5321234567']),
    );
    expect(result.error?.code, 'netgsm_invalid_body');
    expect(result.status, DeliveryStatus.failed);
    expect(calls, 0);
  });
}
