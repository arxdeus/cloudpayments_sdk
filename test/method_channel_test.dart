import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the wire contract with the native side.
///
/// Every other test substitutes a fake platform, so without this file the
/// channel name, the method names and the argument keys — the one part that
/// has to match Kotlin and Swift exactly — would go unchecked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final platform = MethodChannelCloudpaymentsSdk();
  final calls = <MethodCall>[];

  Object? reply;
  PlatformException? failWith;

  void mock() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, (call) async {
      calls.add(call);
      final failure = failWith;
      if (failure != null) throw failure;
      return reply;
    });
  }

  setUp(() {
    calls.clear();
    reply = null;
    failWith = null;
    mock();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform.methodChannel, null);
  });

  test('uses the channel name both native sides register', () {
    expect(
      platform.methodChannel.name,
      'dev.arxdeus.flutter/cloudpayments_sdk',
    );
  });

  group('createCryptogram', () {
    test('sends every argument the native SDKs need', () async {
      reply = 'PACKET';

      final cryptogram = await platform.createCryptogram(
        cardNumber: '4111111111111111',
        expiryDate: '12/30',
        cvv: '123',
        publicId: 'pk_test',
        publicKey: '-----BEGIN PUBLIC KEY-----MIIB',
        keyVersion: 13,
      );

      expect(cryptogram, 'PACKET');
      expect(calls, hasLength(1));
      expect(calls.single.method, 'createCryptogram');
      expect(calls.single.arguments, <String, dynamic>{
        'cardNumber': '4111111111111111',
        'expiryDate': '12/30',
        'cvv': '123',
        'publicId': 'pk_test',
        'publicKey': '-----BEGIN PUBLIC KEY-----MIIB',
        'keyVersion': 13,
      });
    });

    test('treats an empty cryptogram as a failure, not a value', () async {
      reply = '';

      await expectLater(
        platform.createCryptogram(
          cardNumber: '4111111111111111',
          expiryDate: '12/30',
          cvv: '123',
          publicId: 'pk_test',
          publicKey: 'KEY',
          keyVersion: 13,
        ),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'cryptogram_failed')),
      );
    });

    test('lets a native error through as a PlatformException', () async {
      failWith = PlatformException(code: 'cryptogram_failed', message: 'nope');

      await expectLater(
        platform.createCryptogram(
          cardNumber: '4111111111111111',
          expiryDate: '12/30',
          cvv: '123',
          publicId: 'pk_test',
          publicKey: 'KEY',
          keyVersion: 13,
        ),
        throwsA(isA<PlatformException>()
            .having((e) => e.message, 'message', 'nope')),
      );
    });
  });

  group('show3ds', () {
    Future<ThreeDsResult> call() => platform.show3ds(
          acsUrl: 'https://acs.example/auth',
          paReq: 'PAREQ',
          md: '504',
        );

    test('sends the three fields the issuer form needs', () async {
      reply = <String, Object?>{'status': 'cancelled'};

      await call();

      final show3dsCall = calls.where((call) => call.method == 'show3ds').single;
      expect(show3dsCall.arguments, <String, dynamic>{
        'acsUrl': 'https://acs.example/auth',
        'paReq': 'PAREQ',
        'md': '504',
      });
    });

    test('decodes a completed authentication', () async {
      reply = <String, Object?>{
        'status': 'success',
        'md': '504',
        'paRes': 'PARES',
      };

      final result = await call();

      expect(result, isA<ThreeDsSuccess>());
      final success = result as ThreeDsSuccess;
      expect(success.md, '504');
      expect(success.paRes, 'PARES');
    });

    test('decodes a cancellation', () async {
      reply = <String, Object?>{'status': 'cancelled'};
      expect(await call(), isA<ThreeDsCancelled>());
    });

    test('decodes a failure, carrying the message and the raw page', () async {
      reply = <String, Object?>{
        'status': 'failure',
        'message': 'ACS said no',
        'html': '<html/>',
      };

      final result = await call();

      expect(result, isA<ThreeDsFailure>());
      final failure = result as ThreeDsFailure;
      expect(failure.message, 'ACS said no');
      expect(failure.html, '<html/>');
    });

    test('treats an unrecognised status as a failure, never as success',
        () async {
      reply = <String, Object?>{'status': 'something-new'};
      expect(await call(), isA<ThreeDsFailure>());
    });

    test('treats a null answer as a cancellation', () async {
      reply = null;
      expect(await call(), isA<ThreeDsCancelled>());
    });
  });

  test('nativeSdkVersion passes the value through', () async {
    reply = '2.1.5';
    expect(await platform.nativeSdkVersion(), '2.1.5');
    expect(calls.single.method, 'nativeSdkVersion');
  });
}
