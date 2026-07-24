import 'dart:convert';

import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _publicId = 'pk_test123';

/// Captures the last request so assertions can be made about the wire format.
class _Recorder {
  http.BaseRequest? request;
  String? body;
}

(CloudpaymentsApiClient, _Recorder) _clientReturning(
  Object? Function(http.Request request) respond, {
  String? apiSecret,
}) {
  final recorder = _Recorder();
  final client = MockClient((request) async {
    recorder
      ..request = request
      ..body = request.body;
    final response = respond(request);
    if (response is http.Response) return response;
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return (
    CloudpaymentsApiClient(
      publicId: _publicId,
      apiSecret: apiSecret,
      httpClient: client,
    ),
    recorder,
  );
}

const _cardRequest = CardPaymentRequest(
  amount: 10,
  cryptogram: 'CRYPTOGRAM',
  ipAddress: '127.0.0.1',
  invoiceId: 'INV-1',
  email: 'buyer@example.com',
);

void main() {
  group('request shape', () {
    test('charge sends the field names CloudPayments expects', () async {
      final (client, recorder) = _clientReturning(
        (_) => {
          'Success': true,
          'Message': null,
          'Model': {'TransactionId': 1, 'Status': 'Completed'},
        },
      );

      await client.charge(_cardRequest);

      final body = jsonDecode(recorder.body!) as Map<String, dynamic>;
      expect(body['Amount'], '10.00');
      expect(body['Currency'], 'RUB');
      expect(body['CardCryptogramPacket'], 'CRYPTOGRAM');
      expect(body['Name'], 'Cloudpayments SDK');
      expect(body['IpAddress'], '127.0.0.1');
      expect(body['InvoiceId'], 'INV-1');
      expect(body['Email'], 'buyer@example.com');
      expect(body['PublicId'], _publicId);
      // Lowercase, exactly as both native SDKs send it.
      expect(body['scenario'], 7);
    });

    test('omits fields that were not set', () async {
      final (client, recorder) = _clientReturning(
        (_) => {'Success': true, 'Model': <String, dynamic>{}},
      );

      await client.charge(
        const CardPaymentRequest(
          amount: 1,
          cryptogram: 'C',
        ),
      );

      final body = jsonDecode(recorder.body!) as Map<String, dynamic>;
      expect(body.containsKey('InvoiceId'), isFalse);
      expect(body.containsKey('Email'), isFalse);
      expect(body.containsKey('Payer'), isFalse);
      expect(body.containsKey('JsonData'), isFalse);
      expect(body.containsKey('SaveCard'), isFalse);
    });

    test('authenticates with the Public ID as a query parameter', () async {
      final (client, recorder) = _clientReturning(
        (_) => {'Success': true, 'Model': <String, dynamic>{}},
      );

      await client.charge(_cardRequest);

      expect(recorder.request!.url.queryParameters['publicId'], _publicId);
      expect(recorder.request!.url.path, '/payments/cards/charge');
      expect(recorder.request!.headers['MobileSDKSource'], isNotNull);
      // No secret configured, so no Basic auth header.
      expect(recorder.request!.headers.containsKey('Authorization'), isFalse);
    });

    test('adds Basic auth when an API secret is configured', () async {
      final (client, recorder) = _clientReturning(
        (_) => {'Success': true, 'Model': <String, dynamic>{}},
        apiSecret: 'secret',
      );

      await client.charge(_cardRequest);

      final expected = base64Encode(utf8.encode('$_publicId:secret'));
      expect(recorder.request!.headers['Authorization'], 'Basic $expected');
    });

    test('folds a receipt and extra data into JsonData', () async {
      final (client, recorder) = _clientReturning(
        (_) => {'Success': true, 'Model': <String, dynamic>{}},
      );

      await client.charge(
        PaymentDetails(
          amount: 100,
          jsonData: const {'orderSource': 'app'},
          receipt: Receipt(
            items: [ReceiptItem(label: 'Coffee', price: 100)],
            taxationSystem: TaxationSystem.simplifiedIncome,
            email: 'buyer@example.com',
          ),
        ).asCardPayment(cryptogram: 'C'),
      );

      final body = jsonDecode(recorder.body!) as Map<String, dynamic>;
      final jsonData =
          jsonDecode(body['JsonData'] as String) as Map<String, dynamic>;
      expect(jsonData['orderSource'], 'app');
      final receipt = (jsonData['CloudPayments']
          as Map<String, dynamic>)['CustomerReceipt'] as Map<String, dynamic>;
      expect(receipt['taxationSystem'], 1);
      expect(
          (receipt['Items'] as List).single, containsPair('label', 'Coffee'));
      expect(receipt['amounts'], containsPair('electronic', 100.0));
    });
  });

  group('charge outcomes', () {
    test('Success:true is a completed payment', () async {
      final (client, _) = _clientReturning(
        (_) => {
          'Success': true,
          'Model': {
            'TransactionId': 42,
            'Status': 'Completed',
            'Amount': 10.0,
            'Currency': 'RUB',
            'CardFirstSix': '411111',
            'CardLastFour': '1111',
            'Token': 'tok_1',
          },
        },
      );

      final result = await client.charge(_cardRequest);

      expect(result, isA<PaymentSuccess>());
      final success = result as PaymentSuccess;
      expect(success.transaction.transactionId, 42);
      expect(success.transaction.status, TransactionStatus.completed);
      expect(success.transaction.maskedCard, '411111******1111');
      expect(success.token, 'tok_1');
      expect(result.isSuccess, isTrue);
    });

    test('Success:false with AcsUrl and PaReq is a 3-D Secure challenge',
        () async {
      final (client, _) = _clientReturning(
        (_) => {
          'Success': false,
          'Message': null,
          'Model': {
            'TransactionId': 504,
            'PaReq': 'PAREQ',
            'AcsUrl': 'https://acs.example/auth',
            'ThreeDsCallbackId': 'cb-1',
          },
        },
      );

      final result = await client.charge(_cardRequest);

      expect(result, isA<PaymentRequiresThreeDs>());
      final pending = result as PaymentRequiresThreeDs;
      expect(pending.challenge.transactionId, 504);
      expect(pending.challenge.acsUrl, 'https://acs.example/auth');
      expect(pending.challenge.paReq, 'PAREQ');
      expect(pending.challenge.threeDsCallbackId, 'cb-1');
    });

    test('Success:false without a challenge is a decline', () async {
      final (client, _) = _clientReturning(
        (_) => {
          'Success': false,
          'Message': null,
          'Model': {
            'TransactionId': 7,
            'Status': 'Declined',
            'ReasonCode': 5051,
            'Reason': 'InsufficientFunds',
            'CardHolderMessage': 'Недостаточно средств на карте',
          },
        },
      );

      final result = await client.charge(_cardRequest);

      expect(result, isA<PaymentDeclined>());
      final declined = result as PaymentDeclined;
      expect(declined.reasonCode, 5051);
      expect(declined.cardHolderMessage, 'Недостаточно средств на карте');
      expect(declined.transaction.isDeclined, isTrue);
    });

    test('Success:true with no Model is unknown, not a failure', () async {
      final (client, _) = _clientReturning(
        (_) => {'Success': true, 'Message': 'ok'},
      );

      // Reporting "failed" here would invite a retry of a payment that may
      // already have gone through.
      await expectLater(
        client.charge(_cardRequest),
        throwsA(
          isA<CloudpaymentsNetworkException>()
              .having((e) => e.message, 'message', contains('unknown')),
        ),
      );
    });

    test('Success:false with no Model is a rejected request', () async {
      final (client, _) = _clientReturning(
        (_) => {'Success': false, 'Message': 'Amount is required'},
      );

      await expectLater(
        client.charge(_cardRequest),
        throwsA(
          isA<CloudpaymentsApiException>().having(
            (e) => e.message,
            'message',
            'Amount is required',
          ),
        ),
      );
    });
  });

  group('transport failures', () {
    test('a 5xx becomes a network exception', () async {
      final (client, _) = _clientReturning((_) => http.Response('oops', 503));

      await expectLater(
        client.charge(_cardRequest),
        throwsA(
          isA<CloudpaymentsNetworkException>()
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('a 401 becomes an API exception naming the credentials', () async {
      final (client, _) = _clientReturning((_) => http.Response('no', 401));

      await expectLater(
        client.charge(_cardRequest),
        throwsA(
          isA<CloudpaymentsApiException>()
              .having((e) => e.message, 'message', contains('Public ID')),
        ),
      );
    });

    test('an unreadable body becomes a network exception', () async {
      final (client, _) =
          _clientReturning((_) => http.Response('<html/>', 200));

      await expectLater(
        client.charge(_cardRequest),
        throwsA(isA<CloudpaymentsNetworkException>()),
      );
    });

    test('a socket-level failure becomes a network exception', () async {
      final client = CloudpaymentsApiClient(
        publicId: _publicId,
        httpClient: MockClient((_) async => throw http.ClientException('down')),
      );

      await expectLater(
        client.charge(_cardRequest),
        throwsA(
          isA<CloudpaymentsNetworkException>()
              .having((e) => e.message, 'message', contains('down')),
        ),
      );
    });
  });

  group('public key', () {
    test('parses Pem and Version', () async {
      final (client, recorder) = _clientReturning(
        (_) => {'Pem': '-----BEGIN PUBLIC KEY-----MIIB', 'Version': 4},
      );

      final key = await client.getPublicKey();

      expect(key.pem, '-----BEGIN PUBLIC KEY-----MIIB');
      expect(key.version, 4);
      expect(recorder.request!.method, 'GET');
      expect(recorder.request!.url.path, '/payments/publickey');
    });

    test('an empty key is an API error, not a silent success', () async {
      final (client, _) = _clientReturning((_) => {'Pem': '', 'Version': 4});

      await expectLater(
        client.getPublicKey(),
        throwsA(isA<CloudpaymentsApiException>()),
      );
    });
  });

  group('completeThreeDs', () {
    http.Response redirect(String location) =>
        http.Response('', 302, headers: {'location': location});

    test('sends MD as a JSON document alongside PaRes', () async {
      final (client, recorder) = _clientReturning(
        (_) => redirect('${CloudpaymentsApiClient.threeDsSuccessUrl}?x=1'),
      );

      await client.completeThreeDs(
        transactionId: 504,
        paRes: 'PARES',
        threeDsCallbackId: 'cb-1',
      );

      final body = jsonDecode(recorder.body!) as Map<String, dynamic>;
      expect(body['PaRes'], 'PARES');
      final md = jsonDecode(body['MD'] as String) as Map<String, dynamic>;
      expect(md['TransactionId'], '504');
      expect(md['ThreeDsCallbackId'], 'cb-1');
      expect(md['SuccessUrl'], CloudpaymentsApiClient.threeDsSuccessUrl);
      expect(md['FailUrl'], CloudpaymentsApiClient.threeDsFailUrl);
      expect(recorder.request!.url.path, '/payments/ThreeDSCallback');
    });

    test('does not follow the redirect that carries the answer', () async {
      final (client, recorder) = _clientReturning(
        (_) => redirect(CloudpaymentsApiClient.threeDsSuccessUrl),
      );

      await client.completeThreeDs(transactionId: 1, paRes: 'PARES');

      // The outcome lives in the Location header. Following the redirect would
      // consume it and leave nothing to read.
      expect(recorder.request!.followRedirects, isFalse);
    });

    test('reads success from the redirect target', () async {
      final (client, _) = _clientReturning(
        (_) => redirect(CloudpaymentsApiClient.threeDsSuccessUrl),
      );

      final result = await client.completeThreeDs(
        transactionId: 1,
        paRes: 'PARES',
      );

      expect(result.success, isTrue);
    });

    test('reads failure, reason code and cardholder message', () async {
      final (client, _) = _clientReturning(
        (_) => redirect(
          '${CloudpaymentsApiClient.threeDsFailUrl}'
          '?ReasonCode=5206&CardHolderMessage=Not+authenticated',
        ),
      );

      final result = await client.completeThreeDs(
        transactionId: 1,
        paRes: 'PARES',
      );

      expect(result.success, isFalse);
      expect(result.reasonCode, 5206);
      expect(result.cardHolderMessage, 'Not authenticated');
    });

    test('accepts a bare boolean body', () async {
      final (client, _) = _clientReturning((_) => http.Response('true', 200));

      final result = await client.completeThreeDs(
        transactionId: 1,
        paRes: 'PARES',
      );

      expect(result.success, isTrue);
    });

    test('does not guess from a redirect it does not recognise', () async {
      final (client, _) = _clientReturning(
        (_) => redirect('https://example.com/somewhere-else'),
      );

      await expectLater(
        client.completeThreeDs(transactionId: 77, paRes: 'PARES'),
        throwsA(
          isA<CloudpaymentsNetworkException>()
              .having((e) => e.message, 'message', contains('77')),
        ),
      );
    });

    test('does not guess success from an unreadable 200', () async {
      final (client, _) =
          _clientReturning((_) => http.Response('<html>ok</html>', 200));

      await expectLater(
        client.completeThreeDs(transactionId: 99, paRes: 'PARES'),
        throwsA(
          isA<CloudpaymentsNetworkException>()
              .having((e) => e.message, 'message', contains('99')),
        ),
      );
    });
  });

  group('endpoints that need the API secret', () {
    late CloudpaymentsApiClient client;

    setUp(() {
      client = CloudpaymentsApiClient(
        publicId: _publicId,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
    });

    test('refuse to run without one, and say why', () async {
      for (final call in <(String, Future<void> Function())>[
        ('confirm', () => client.confirm(transactionId: 1, amount: 1)),
        ('voidPayment', () => client.voidPayment(1)),
        ('refund', () => client.refund(transactionId: 1, amount: 1)),
        ('getTransaction', () => client.getTransaction(1)),
        ('testConnection', () => client.testConnection()),
        ('post3ds', () => client.post3ds(transactionId: 1, paRes: 'p')),
        (
          'chargeToken',
          () => client.chargeToken(
                const TokenPaymentRequest(
                  amount: 1,
                  token: 't',
                  accountId: 'a',
                ),
              ),
        ),
        (
          'authToken',
          () => client.authToken(
                const TokenPaymentRequest(
                  amount: 1,
                  token: 't',
                  accountId: 'a',
                ),
              ),
        ),
      ]) {
        await expectLater(
          call.$2(),
          throwsA(
            isA<CloudpaymentsConfigurationException>().having(
              (e) => e.message,
              'message for ${call.$1}',
              allOf(contains(call.$1), contains('backend')),
            ),
          ),
        );
      }
    });

    test('hasApiSecret reflects the configuration', () {
      expect(client.hasApiSecret, isFalse);
      expect(
        CloudpaymentsApiClient(publicId: _publicId, apiSecret: 's')
            .hasApiSecret,
        isTrue,
      );
    });
  });

  group('construction', () {
    test('rejects an empty Public ID', () {
      expect(
        () => CloudpaymentsApiClient(publicId: ''),
        throwsA(isA<CloudpaymentsConfigurationException>()),
      );
    });
  });
}
