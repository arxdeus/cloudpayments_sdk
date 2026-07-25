import 'dart:convert';

import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Captures what the ready-made form is asked to show, and answers with
/// whatever the test needs.
class _FakeFormPlatform extends CloudpaymentsSdkPlatform
    with MockPlatformInterfaceMixin {
  _FakeFormPlatform({
    this.answer = const {'status': 'succeeded', 'transactionId': 900},
    this.error,
  });

  final Map<Object?, Object?> answer;
  final Object? error;

  Map<String, dynamic>? lastArguments;
  int calls = 0;

  @override
  Future<Map<Object?, Object?>> presentPaymentForm(
    Map<String, dynamic> arguments,
  ) async {
    calls++;
    lastArguments = arguments;
    final failure = error;
    if (failure != null) throw failure;
    return answer;
  }
}

CloudpaymentsSdk _sdk(_FakeFormPlatform platform) =>
    CloudpaymentsSdk(publicId: 'pk_test123', platform: platform);

void main() {
  group('presentPaymentForm arguments', () {
    test('sends the payment in the shape the native forms take', () async {
      final platform = _FakeFormPlatform();

      await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(
          amount: 499,
          currency: Currency.rub,
          invoiceId: 'ORDER-7',
          description: 'Подписка',
          accountId: 'user-42',
          email: 'user@example.com',
          payer: Payer(firstName: 'Ivan', country: 'RU'),
        ),
      );

      final args = platform.lastArguments!;
      expect(args['publicId'], 'pk_test123');
      // A string, like the API and both native SDKs expect.
      expect(args['amount'], '499.00');
      expect(args['currency'], 'RUB');
      // The native forms call it externalId / invoiceId, never InvoiceId.
      expect(args['invoiceId'], 'ORDER-7');
      expect(args['description'], 'Подписка');
      expect(args['accountId'], 'user-42');
      expect(args['email'], 'user@example.com');
      expect(args['payer'], {'FirstName': 'Ivan', 'Country': 'RU'});
    });

    test('passes a receipt as a receipt, not folded into JsonData', () async {
      final platform = _FakeFormPlatform();

      await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(
          amount: 150,
          receipt: Receipt(
            items: [ReceiptItem(label: 'Coffee', price: 150)],
            taxationSystem: TaxationSystem.simplifiedIncome,
          ),
        ),
      );

      final args = platform.lastArguments!;
      final receipt = args['receipt']! as Map<String, dynamic>;
      expect(receipt['taxationSystem'], 1);
      expect(
          (receipt['Items']! as List).single, containsPair('label', 'Coffee'));
      // The form takes a receipt field of its own; wrapping it in JsonData
      // would register it twice.
      expect(args.containsKey('jsonData'), isFalse);
    });

    test('serialises extra data as a JSON string', () async {
      final platform = _FakeFormPlatform();

      await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(
          amount: 10,
          jsonData: {'source': 'app', 'campaign': 42},
        ),
      );

      final decoded = jsonDecode(platform.lastArguments!['jsonData']! as String)
          as Map<String, dynamic>;
      expect(decoded, {'source': 'app', 'campaign': 42});
    });

    test('flattens the form options', () async {
      final platform = _FakeFormPlatform();

      await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 10),
        options: const PaymentFormOptions(
          twoStage: true,
          emailBehavior: EmailFieldBehavior.required,
          methodOrder: [
            CloudpaymentsPaymentMethod.tPay,
            CloudpaymentsPaymentMethod.card,
          ],
          singleMethod: CloudpaymentsPaymentMethod.sbp,
          showResultScreen: false,
          testMode: true,
        ),
      );

      final args = platform.lastArguments!;
      expect(args['twoStage'], isTrue);
      expect(args['emailBehavior'], 'REQUIRED');
      // The wire names are the ones the native SDKs match on.
      expect(args['methodOrder'], ['TinkoffPay', 'Card']);
      expect(args['singleMethod'], 'Sbp');
      expect(args['showResultScreen'], isFalse);
      expect(args['testMode'], isTrue);
    });
  });

  group('subscriptions', () {
    test('sends the recurrent block the native SDKs take', () async {
      final platform = _FakeFormPlatform();

      await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 499, accountId: 'user-42'),
        recurrent: const CloudpaymentsRecurrent(
          interval: RecurrentInterval.month,
          period: 1,
          amount: 399,
          startDate: '2026-08-25',
          maxPeriods: 12,
        ),
      );

      expect(platform.lastArguments!['recurrent'], {
        'interval': 'Month',
        'period': 1,
        'amount': 399,
        'startDate': '2026-08-25',
        'maxPeriods': 12,
      });
    });

    test('carries a per-charge receipt under "receipt"', () async {
      final platform = _FakeFormPlatform();

      await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 499, accountId: 'user-42'),
        recurrent: const CloudpaymentsRecurrent(
          interval: RecurrentInterval.month,
          period: 1,
          receipt: Receipt(items: [ReceiptItem(label: 'Про', price: 499)]),
        ),
      );

      final recurrent =
          platform.lastArguments!['recurrent']! as Map<String, dynamic>;
      // CloudPayments renamed customerReceipt to receipt; both 2.x SDKs send
      // the new name.
      expect(recurrent.containsKey('receipt'), isTrue);
      expect(recurrent.containsKey('customerReceipt'), isFalse);
    });

    test('refuses a subscription without an accountId', () async {
      final platform = _FakeFormPlatform();

      await expectLater(
        _sdk(platform).presentPaymentForm(
          details: const PaymentDetails(amount: 499),
          recurrent: const CloudpaymentsRecurrent(
            interval: RecurrentInterval.month,
            period: 1,
          ),
        ),
        throwsA(
          isA<CloudpaymentsConfigurationException>()
              .having((e) => e.message, 'message', contains('accountId')),
        ),
      );
      expect(platform.calls, 0);
    });

    test('the low-level charge path folds it into JsonData', () {
      final request = const PaymentDetails(
        amount: 499,
        accountId: 'user-42',
        recurrent: CloudpaymentsRecurrent(
          interval: RecurrentInterval.week,
          period: 2,
        ),
      ).asCardPayment(cryptogram: 'C');

      final jsonData = jsonDecode(request.toJson()['JsonData']! as String)
          as Map<String, dynamic>;
      expect(
        (jsonData['CloudPayments']! as Map<String, dynamic>)['recurrent'],
        {'interval': 'Week', 'period': 2},
      );
    });

    test('a receipt and a subscription share the CloudPayments wrapper', () {
      final request = const PaymentDetails(
        amount: 499,
        accountId: 'user-42',
        receipt: Receipt(items: [ReceiptItem(label: 'Про', price: 499)]),
        recurrent: CloudpaymentsRecurrent(
          interval: RecurrentInterval.month,
          period: 1,
        ),
      ).asCardPayment(cryptogram: 'C');

      final wrapper = (jsonDecode(request.toJson()['JsonData']! as String)
          as Map<String, dynamic>)['CloudPayments']! as Map<String, dynamic>;
      expect(wrapper.containsKey('CustomerReceipt'), isTrue);
      expect(wrapper.containsKey('recurrent'), isTrue);
    });
  });

  group('presentPaymentForm results', () {
    test('a finished payment', () async {
      final platform = _FakeFormPlatform(
        answer: const {'status': 'succeeded', 'transactionId': 900},
      );

      final result = await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 10),
      );

      expect(result, isA<FormPaymentSucceeded>());
      expect(result.transactionId, 900);
      expect(result.isSuccess, isTrue);
    });

    test('a declined payment carries the reason code', () async {
      final platform = _FakeFormPlatform(
        answer: const {
          'status': 'failed',
          'transactionId': 901,
          'reasonCode': 5051,
        },
      );

      final result = await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 10),
      );

      expect(result, isA<FormPaymentFailed>());
      expect((result as FormPaymentFailed).reasonCode, 5051);
      expect(result.transactionId, 901);
    });

    test('a closed form', () async {
      final platform = _FakeFormPlatform(answer: const {'status': 'closed'});

      final result = await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 10),
      );

      expect(result, isA<FormPaymentClosed>());
      expect(result.transactionId, isNull);
      expect(result.isSuccess, isFalse);
    });

    test('Android zeroes read as absent, not as transaction 0', () async {
      final platform = _FakeFormPlatform(
        answer: const {
          'status': 'failed',
          'transactionId': 0,
          'reasonCode': 0,
        },
      );

      final result = await _sdk(platform).presentPaymentForm(
        details: const PaymentDetails(amount: 10),
      );

      expect(result.transactionId, isNull);
      expect((result as FormPaymentFailed).reasonCode, isNull);
    });

    test('an unrecognised status is a failure, never a success', () async {
      final platform = _FakeFormPlatform(answer: const {'status': 'wat'});

      expect(
        await _sdk(platform).presentPaymentForm(
          details: const PaymentDetails(amount: 10),
        ),
        isA<FormPaymentFailed>(),
      );
    });

    test('a native error becomes a configuration exception', () async {
      final platform = _FakeFormPlatform(
        error: PlatformException(code: 'no_activity', message: 'no activity'),
      );

      await expectLater(
        _sdk(platform).presentPaymentForm(
          details: const PaymentDetails(amount: 10),
        ),
        throwsA(
          isA<CloudpaymentsConfigurationException>()
              .having((e) => e.message, 'message', 'no activity'),
        ),
      );
    });

    test('an unregistered plugin says so plainly', () async {
      final platform = _FakeFormPlatform(
        error: MissingPluginException('no impl'),
      );

      await expectLater(
        _sdk(platform).presentPaymentForm(
          details: const PaymentDetails(amount: 10),
        ),
        throwsA(
          isA<CloudpaymentsConfigurationException>()
              .having((e) => e.message, 'message', contains('Android and iOS')),
        ),
      );
    });
  });
}
