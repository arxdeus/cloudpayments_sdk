import 'dart:convert';

import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A stand-in for the native side, so the whole payment cycle can be tested
/// without a device.
class _FakePlatform extends CloudpaymentsSdkPlatform
    with MockPlatformInterfaceMixin {
  _FakePlatform({
    this.threeDsResult = const ThreeDsSuccess(md: '504', paRes: 'PARES'),
    this.cryptogramError,
  }) : cryptogram = 'CRYPTOGRAM';

  final String cryptogram;
  final ThreeDsResult threeDsResult;
  final PlatformException? cryptogramError;

  int cryptogramCalls = 0;
  int threeDsCalls = 0;
  Map<String, Object?> lastCryptogramArgs = const {};
  Map<String, Object?> lastThreeDsArgs = const {};

  @override
  Future<String> createCryptogram({
    required String cardNumber,
    required String expiryDate,
    required String cvv,
    required String publicId,
    required String publicKey,
    required int keyVersion,
  }) async {
    cryptogramCalls++;
    lastCryptogramArgs = {
      'cardNumber': cardNumber,
      'expiryDate': expiryDate,
      'cvv': cvv,
      'publicId': publicId,
      'publicKey': publicKey,
      'keyVersion': keyVersion,
    };
    final error = cryptogramError;
    if (error != null) throw error;
    return cryptogram;
  }

  @override
  Future<ThreeDsResult> show3ds({
    required String acsUrl,
    required String paReq,
    required String md,
  }) async {
    threeDsCalls++;
    lastThreeDsArgs = {'acsUrl': acsUrl, 'paReq': paReq, 'md': md};
    return threeDsResult;
  }

  @override
  Future<String?> nativeSdkVersion() async => '2.1.5';
}

const _publicKeyResponse = {
  'Pem': '-----BEGIN PUBLIC KEY-----MIIBTEST',
  'Version': 4,
};

const _threeDsChallenge = {
  'Success': false,
  'Message': null,
  'Model': {
    'TransactionId': 504,
    'PaReq': 'PAREQ',
    'AcsUrl': 'https://acs.example/auth',
    'ThreeDsCallbackId': 'cb-1',
  },
};

const _card = CardData(
  number: '4111 1111 1111 1111',
  expiryDate: '12/30',
  cvv: '123',
);

const _details = PaymentDetails(amount: 10, ipAddress: '127.0.0.1');

/// Builds an SDK whose HTTP layer answers from [routes], keyed by URL path.
(CloudpaymentsSdk, _FakePlatform, List<String>) _sdk(
  Map<String, Object? Function(http.Request)> routes, {
  _FakePlatform? platform,
}) {
  final calls = <String>[];
  final fake = platform ?? _FakePlatform();
  final client = MockClient((request) async {
    calls.add(request.url.path);
    final handler = routes[request.url.path];
    if (handler == null) {
      return http.Response('{"Success":false,"Message":"no route"}', 404);
    }
    final response = handler(request);
    if (response is http.Response) return response;
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  final sdk = CloudpaymentsSdk(
    publicId: 'pk_test123',
    platform: fake,
    httpClient: client,
  );
  return (sdk, fake, calls);
}

void main() {
  group('createCryptogram', () {
    test('passes the fetched key and a normalised expiry to the native side',
        () async {
      final (sdk, fake, _) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
      });

      final cryptogram = await sdk.createCryptogram(
        const CardData(
          number: '4111 1111 1111 1111',
          expiryDate: '1230',
          cvv: '123',
        ),
      );

      expect(cryptogram, 'CRYPTOGRAM');
      expect(fake.lastCryptogramArgs['cardNumber'], '4111111111111111');
      expect(fake.lastCryptogramArgs['expiryDate'], '12/30');
      expect(fake.lastCryptogramArgs['publicKey'], _publicKeyResponse['Pem']);
      expect(fake.lastCryptogramArgs['keyVersion'], 4);
      expect(fake.lastCryptogramArgs['publicId'], 'pk_test123');
    });

    test('rejects a card number the native SDKs cannot handle', () async {
      final (sdk, fake, _) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
      });

      // 13 digits with a *valid* Luhn checksum: a real Visa format that
      // CloudPayments still cannot process, so the length floor is what has to
      // reject it — not the checksum.
      expect(CardUtils.passesLuhn('4222222222222'), isTrue);

      await expectLater(
        sdk.createCryptogram(
          const CardData(
            number: '4222222222222',
            expiryDate: '12/30',
            cvv: '123',
          ),
        ),
        throwsA(
          isA<CloudpaymentsCryptogramException>()
              .having((e) => e.code, 'code', 'invalid_card_number'),
        ),
      );
      // Rejected before the network and before the platform channel.
      expect(fake.cryptogramCalls, 0);
      // And isValidNumber agrees, so a form cannot bless what pay() refuses.
      expect(CardUtils.isValidNumber('4222222222222'), isFalse);
    });

    test('rejects an unparseable expiry date', () async {
      final (sdk, _, _) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
      });

      await expectLater(
        sdk.createCryptogram(
          const CardData(
            number: '4111111111111111',
            expiryDate: '99/99',
            cvv: '123',
          ),
        ),
        throwsA(
          isA<CloudpaymentsCryptogramException>()
              .having((e) => e.code, 'code', 'invalid_expiry_date'),
        ),
      );
    });

    test('turns a native failure into a cryptogram exception', () async {
      final (sdk, _, _) = _sdk(
        {'/payments/publickey': (_) => _publicKeyResponse},
        platform: _FakePlatform(
          cryptogramError: PlatformException(
            code: 'cryptogram_failed',
            message: 'nope',
          ),
        ),
      );

      await expectLater(
        sdk.createCryptogram(_card),
        throwsA(
          isA<CloudpaymentsCryptogramException>()
              .having((e) => e.message, 'message', 'nope'),
        ),
      );
    });
  });

  group('publicKey caching', () {
    test('fetches once and reuses the result', () async {
      final (sdk, _, calls) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
      });

      await sdk.publicKey();
      await sdk.publicKey();
      await sdk.publicKey();

      expect(calls.where((p) => p == '/payments/publickey'), hasLength(1));
    });

    test('concurrent callers share one request', () async {
      final (sdk, _, calls) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
      });

      await Future.wait([sdk.publicKey(), sdk.publicKey(), sdk.publicKey()]);

      expect(calls.where((p) => p == '/payments/publickey'), hasLength(1));
    });

    test('a failed fetch is not cached', () async {
      var attempts = 0;
      final (sdk, _, _) = _sdk({
        '/payments/publickey': (_) {
          attempts++;
          if (attempts == 1) return http.Response('down', 503);
          return _publicKeyResponse;
        },
      });

      await expectLater(
        sdk.publicKey(),
        throwsA(isA<CloudpaymentsNetworkException>()),
      );
      final key = await sdk.publicKey();

      expect(key.version, 4);
      expect(attempts, 2);
    });

    test('warmUp swallows failures', () async {
      final (sdk, _, _) = _sdk({
        '/payments/publickey': (_) => http.Response('down', 503),
      });

      await expectLater(sdk.warmUp(), completes);
    });
  });

  group('pay', () {
    test('runs cryptogram, charge and reports success', () async {
      final (sdk, fake, calls) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
        '/payments/cards/charge': (_) => {
              'Success': true,
              'Model': {'TransactionId': 42, 'Status': 'Completed'},
            },
      });

      final result = await sdk.pay(card: _card, details: _details);

      expect(result, isA<PaymentSuccess>());
      expect((result as PaymentSuccess).transaction.transactionId, 42);
      expect(fake.cryptogramCalls, 1);
      expect(fake.threeDsCalls, 0);
      expect(calls, contains('/payments/cards/charge'));
    });

    test('twoStage goes to auth instead of charge', () async {
      final (sdk, _, calls) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
        '/payments/cards/auth': (_) => {
              'Success': true,
              'Model': {'TransactionId': 43, 'Status': 'Authorized'},
            },
      });

      final result = await sdk.pay(
        card: _card,
        details: _details,
        twoStage: true,
      );

      expect(calls, contains('/payments/cards/auth'));
      expect(calls, isNot(contains('/payments/cards/charge')));
      expect(
        (result as PaymentSuccess).transaction.status,
        TransactionStatus.authorized,
      );
    });

    test('sends the cardholder name when one is given', () async {
      String? sentName;
      final (sdk, _, _) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
        '/payments/cards/charge': (request) {
          sentName = (jsonDecode(request.body) as Map<String, dynamic>)['Name']
              as String;
          return {
            'Success': true,
            'Model': {'TransactionId': 1, 'Status': 'Completed'},
          };
        },
      });

      await sdk.pay(
        card: const CardData(
          number: '4111111111111111',
          expiryDate: '12/30',
          cvv: '123',
          holderName: 'IVAN IVANOV',
        ),
        details: _details,
      );

      expect(sentName, 'IVAN IVANOV');
    });

    test('resolves a 3-D Secure challenge and completes the payment', () async {
      final (sdk, fake, calls) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
        '/payments/cards/charge': (_) => _threeDsChallenge,
        '/payments/ThreeDSCallback': (_) => http.Response(
              '',
              302,
              headers: {'location': CloudpaymentsApiClient.threeDsSuccessUrl},
            ),
      });

      final result = await sdk.pay(card: _card, details: _details);

      expect(result, isA<PaymentSuccess>());
      expect(fake.threeDsCalls, 1);
      expect(fake.lastThreeDsArgs['acsUrl'], 'https://acs.example/auth');
      expect(fake.lastThreeDsArgs['paReq'], 'PAREQ');
      // The transaction id is what goes to the issuer as MD.
      expect(fake.lastThreeDsArgs['md'], '504');
      expect(calls, contains('/payments/ThreeDSCallback'));

      // The spent challenge is stripped, so the transaction no longer looks
      // like it is waiting for authentication.
      final transaction = (result as PaymentSuccess).transaction;
      expect(transaction.transactionId, 504);
      expect(transaction.requiresThreeDs, isFalse);
    });

    test('a dismissed 3-D Secure screen is a cancellation, not an error',
        () async {
      final (sdk, _, calls) = _sdk(
        {
          '/payments/publickey': (_) => _publicKeyResponse,
          '/payments/cards/charge': (_) => _threeDsChallenge,
        },
        platform: _FakePlatform(threeDsResult: const ThreeDsCancelled()),
      );

      final result = await sdk.pay(card: _card, details: _details);

      expect(result, isA<PaymentCancelled>());
      expect(result.transaction?.transactionId, 504);
      // Nothing is posted back when the user walks away.
      expect(calls, isNot(contains('/payments/ThreeDSCallback')));
    });

    test('a failed challenge is a failure carrying the issuer message',
        () async {
      final (sdk, _, _) = _sdk(
        {
          '/payments/publickey': (_) => _publicKeyResponse,
          '/payments/cards/charge': (_) => _threeDsChallenge,
        },
        platform: _FakePlatform(
          threeDsResult: const ThreeDsFailure(message: 'ACS said no'),
        ),
      );

      final result = await sdk.pay(card: _card, details: _details);

      expect(result, isA<PaymentFailure>());
      expect((result as PaymentFailure).message, 'ACS said no');
    });

    test('a rejected callback reports the cardholder message and reason',
        () async {
      final (sdk, _, _) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
        '/payments/cards/charge': (_) => _threeDsChallenge,
        '/payments/ThreeDSCallback': (_) => http.Response(
              '',
              302,
              headers: {
                'location': '${CloudpaymentsApiClient.threeDsFailUrl}'
                    '?ReasonCode=5206&CardHolderMessage=Authentication+failed',
              },
            ),
      });

      final result = await sdk.pay(card: _card, details: _details);

      expect(result, isA<PaymentFailure>());
      final failure = result as PaymentFailure;
      expect(failure.message, 'Authentication failed');
      expect(failure.reasonCode, 5206);
    });

    test('a decline never opens the 3-D Secure screen', () async {
      final (sdk, fake, _) = _sdk({
        '/payments/publickey': (_) => _publicKeyResponse,
        '/payments/cards/charge': (_) => {
              'Success': false,
              'Model': {
                'TransactionId': 9,
                'Status': 'Declined',
                'ReasonCode': 5051,
              },
            },
      });

      final result = await sdk.pay(card: _card, details: _details);

      expect(result, isA<PaymentDeclined>());
      expect(fake.threeDsCalls, 0);
    });
  });

  group('payWithCryptogram', () {
    test('skips the native cryptogram step, for wallet tokens', () async {
      String? sentCryptogram;
      String? sentName;
      final (sdk, fake, _) = _sdk({
        '/payments/cards/charge': (request) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentCryptogram = body['CardCryptogramPacket'] as String;
          sentName = body['Name'] as String;
          return {
            'Success': true,
            'Model': {'TransactionId': 5, 'Status': 'Completed'},
          };
        },
      });

      final result = await sdk.payWithCryptogram(
        cryptogram: 'GOOGLE_PAY_TOKEN',
        details: _details,
        cardHolderName: CardPaymentRequest.googlePayCardHolderName,
      );

      expect(result, isA<PaymentSuccess>());
      expect(sentCryptogram, 'GOOGLE_PAY_TOKEN');
      expect(sentName, 'Google Pay');
      expect(fake.cryptogramCalls, 0);
    });
  });

  group('diagnostics', () {
    test('reports the native SDK version', () async {
      final (sdk, _, _) = _sdk({});
      expect(await sdk.nativeSdkVersion(), '2.1.5');
    });
  });
}
