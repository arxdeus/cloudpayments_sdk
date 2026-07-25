import 'dart:convert';

import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Transaction', () {
    test('reads the documented fields with their exact casing', () {
      final transaction = Transaction.fromJson(const {
        'TransactionId': 891463508,
        'Amount': 100.0,
        'Currency': 'RUB',
        'CurrencyCode': 0,
        'InvoiceId': 'INV-1',
        'AccountId': 'user-1',
        'Email': 'buyer@example.com',
        'Description': 'Order',
        'TestMode': true,
        'CardFirstSix': '424242',
        'CardLastFour': '4242',
        'CardExpDate': '12/30',
        'CardType': 'Visa',
        'Issuer': 'Sberbank',
        'IssuerBankCountry': 'RU',
        'Status': 'Completed',
        'StatusCode': 3,
        'Reason': 'Approved',
        'ReasonCode': 0,
        'CardHolderMessage': 'Оплата успешно проведена',
        'AuthCode': 'A1B2C3',
        'CreatedDateIso': '2026-07-24T12:00:00',
        'Token': 'tok_1',
      });

      expect(transaction.transactionId, 891463508);
      expect(transaction.amount, 100.0);
      expect(transaction.currency, 'RUB');
      expect(transaction.invoiceId, 'INV-1');
      expect(transaction.testMode, isTrue);
      expect(transaction.cardSystem, CardSystem.visa);
      expect(transaction.maskedCard, '424242******4242');
      expect(transaction.status, TransactionStatus.completed);
      expect(transaction.statusCode, 3);
      expect(transaction.cardHolderMessage, 'Оплата успешно проведена');
      expect(transaction.authCode, 'A1B2C3');
      expect(transaction.createdDate, DateTime(2026, 7, 24, 12));
      expect(transaction.token, 'tok_1');
      expect(transaction.isSuccessful, isTrue);
      expect(transaction.isDeclined, isFalse);
    });

    test('treats Authorized as successful and Declined as declined', () {
      expect(
        Transaction.fromJson(const {'Status': 'Authorized'}).isSuccessful,
        isTrue,
      );
      expect(
        Transaction.fromJson(const {'Status': 'Declined'}).isDeclined,
        isTrue,
      );
      expect(
        Transaction.fromJson(const {'Status': 'AwaitingAuthentication'}).status,
        TransactionStatus.awaitingAuthentication,
      );
    });

    test('keeps unknown statuses readable instead of guessing', () {
      final transaction = Transaction.fromJson(const {'Status': 'Frobnicated'});
      expect(transaction.status, TransactionStatus.unknown);
      expect(transaction.rawStatus, 'Frobnicated');
      expect(transaction.isSuccessful, isFalse);
    });

    test('copes with numbers arriving as strings', () {
      final transaction = Transaction.fromJson(const {
        'TransactionId': '77',
        'Amount': '10.50',
        'ReasonCode': '5051',
        'TestMode': 'true',
      });

      expect(transaction.transactionId, 77);
      expect(transaction.amount, 10.5);
      expect(transaction.reasonCode, 5051);
      expect(transaction.testMode, isTrue);
    });

    test('missing and empty fields read as null, not as empty strings', () {
      final transaction = Transaction.fromJson(const {'InvoiceId': ''});
      expect(transaction.invoiceId, isNull);
      expect(transaction.email, isNull);
      expect(transaction.maskedCard, isNull);
      expect(transaction.createdDate, isNull);
    });

    test('exposes everything else through raw', () {
      final transaction = Transaction.fromJson(const {
        'EscrowAccumulationId': 'esc-1',
      });
      expect(transaction.raw['EscrowAccumulationId'], 'esc-1');
    });

    group('3-D Secure detection', () {
      test('needs both AcsUrl and PaReq', () {
        expect(
          Transaction.fromJson(const {
            'TransactionId': 1,
            'AcsUrl': 'https://acs.example',
            'PaReq': 'PAREQ',
          }).requiresThreeDs,
          isTrue,
        );
        expect(
          Transaction.fromJson(const {
            'TransactionId': 1,
            'AcsUrl': 'https://acs.example',
          }).requiresThreeDs,
          isFalse,
        );
        expect(
          Transaction.fromJson(const {'TransactionId': 1, 'PaReq': 'PAREQ'})
              .requiresThreeDs,
          isFalse,
        );
        expect(
          Transaction.fromJson(const {
            'TransactionId': 1,
            'AcsUrl': '',
            'PaReq': '',
          }).requiresThreeDs,
          isFalse,
        );
      });

      test('builds a challenge carrying everything the screen needs', () {
        final challenge = Transaction.fromJson(const {
          'TransactionId': 504,
          'AcsUrl': 'https://acs.example',
          'PaReq': 'PAREQ',
          'ThreeDsCallbackId': 'cb-1',
          'IFrameIsAllowed': true,
        }).threeDsChallenge;

        expect(challenge, isNotNull);
        expect(challenge!.transactionId, 504);
        expect(challenge.acsUrl, 'https://acs.example');
        expect(challenge.paReq, 'PAREQ');
        expect(challenge.threeDsCallbackId, 'cb-1');
        expect(challenge.iFrameIsAllowed, isTrue);
      });

      test('is null without a transaction id to authenticate', () {
        expect(
          Transaction.fromJson(const {
            'AcsUrl': 'https://acs.example',
            'PaReq': 'PAREQ',
          }).threeDsChallenge,
          isNull,
        );
      });
    });
  });

  group('PaymentDetails', () {
    test('serialises amounts with two decimals, as a string', () {
      expect(
        const PaymentDetails(amount: 10).toJson()['Amount'],
        '10.00',
      );
      expect(
        const PaymentDetails(amount: 10.5).toJson()['Amount'],
        '10.50',
      );
      expect(
        const PaymentDetails(amount: 1234.567).toJson()['Amount'],
        '1234.57',
      );
    });

    test('defaults to roubles and honours a raw currency override', () {
      expect(const PaymentDetails(amount: 1).currencyCode, 'RUB');
      expect(
        const PaymentDetails(amount: 1, currency: Currency.usd).currencyCode,
        'USD',
      );
      expect(
        const PaymentDetails(amount: 1, rawCurrency: 'MDL').currencyCode,
        'MDL',
      );
    });

    test('drops an all-empty payer instead of sending {}', () {
      expect(
        const PaymentDetails(amount: 1, payer: Payer()).toJson()['Payer'],
        isNull,
      );
      expect(
        const PaymentDetails(amount: 1, payer: Payer(firstName: 'Ivan'))
            .toJson()['Payer'],
        {'FirstName': 'Ivan'},
      );
    });

    test('asCardPayment carries every field across', () {
      final request = const PaymentDetails(
        amount: 99,
        currency: Currency.eur,
        invoiceId: 'INV',
        description: 'Order',
        accountId: 'acc',
        email: 'a@b.c',
        ipAddress: '1.2.3.4',
        cultureName: CultureName.enUs,
        saveCard: true,
      ).asCardPayment(cryptogram: 'C', cardHolderName: 'IVAN');

      final json = request.toJson();
      expect(json['Amount'], '99.00');
      expect(json['Currency'], 'EUR');
      expect(json['InvoiceId'], 'INV');
      expect(json['Description'], 'Order');
      expect(json['AccountId'], 'acc');
      expect(json['Email'], 'a@b.c');
      expect(json['IpAddress'], '1.2.3.4');
      expect(json['CultureName'], 'en-US');
      expect(json['SaveCard'], true);
      expect(json['Name'], 'IVAN');
      expect(json['CardCryptogramPacket'], 'C');
    });

    test('asTokenPayment refuses to build without an accountId', () {
      expect(
        () => const PaymentDetails(amount: 1).asTokenPayment('tok'),
        throwsArgumentError,
      );
      expect(
        const PaymentDetails(amount: 1, accountId: 'acc')
            .asTokenPayment('tok')
            .toJson()['Token'],
        'tok',
      );
    });
  });

  group('Receipt', () {
    test('computes the line total and the electronic amount', () {
      const receipt = Receipt(
        items: [
          ReceiptItem(label: 'Coffee', price: 150, quantity: 2),
          ReceiptItem(label: 'Cake', price: 300, vat: VatRate.vat20),
        ],
      );

      expect(receipt.total, 600);
      final json = receipt.toJson();
      expect((json['Items'] as List).first, containsPair('amount', 300.0));
      expect((json['Items'] as List).last, containsPair('vat', 20));
      expect(json['amounts'], containsPair('electronic', 600.0));
    });

    test('an explicit line amount wins over price * quantity', () {
      const item = ReceiptItem(
        label: 'Discounted',
        price: 100,
        quantity: 3,
        amount: 250,
      );
      expect(item.amount, 250);
    });

    test('vat: none serialises as null, which is "не облагается"', () {
      final json = const ReceiptItem(label: 'X', price: 1).toJson();
      expect(json.containsKey('vat'), isTrue);
      expect(json['vat'], isNull);
    });

    test('merges into existing JsonData rather than replacing it', () {
      final data = const Receipt(items: [ReceiptItem(label: 'X', price: 1)])
          .toJsonData({'orderSource': 'app'});

      expect(data['orderSource'], 'app');
      expect(
        (data['CloudPayments']! as Map<String, dynamic>)['CustomerReceipt'],
        isA<Map<String, dynamic>>(),
      );
      // Round-trips through JSON, which is how it reaches the API.
      expect(() => jsonEncode(data), returnsNormally);
    });
  });

  group('ThreeDsCallbackResult', () {
    const successUrl = 'https://api.cloudpayments.ru/threeds/success';
    const failUrl = 'https://api.cloudpayments.ru/threeds/fail';

    test('matches the sentinel URLs by prefix', () {
      expect(
        ThreeDsCallbackResult.fromRedirect(
          '$successUrl?ReasonCode=0',
          successUrl: successUrl,
          failUrl: failUrl,
        ).success,
        isTrue,
      );
      expect(
        ThreeDsCallbackResult.fromRedirect(
          failUrl,
          successUrl: successUrl,
          failUrl: failUrl,
        ).success,
        isFalse,
      );
    });

    test('an unexpected redirect is unknown, not a failure', () {
      final result = ThreeDsCallbackResult.fromRedirect(
        'https://example.com/elsewhere',
        successUrl: successUrl,
        failUrl: failUrl,
      );
      expect(result.outcomeUnknown, isTrue);
      expect(result.message, contains('unexpected'));
    });

    test('a recognised redirect is never marked unknown', () {
      for (final url in [successUrl, '$failUrl?ReasonCode=5206']) {
        expect(
          ThreeDsCallbackResult.fromRedirect(
            url,
            successUrl: successUrl,
            failUrl: failUrl,
          ).outcomeUnknown,
          isFalse,
        );
      }
    });

    test('reads ReasonCode and CardHolderMessage whatever their casing', () {
      final result = ThreeDsCallbackResult.fromRedirect(
        '$failUrl?reasoncode=5206&cardholdermessage=Nope',
        successUrl: successUrl,
        failUrl: failUrl,
      );
      expect(result.reasonCode, 5206);
      expect(result.cardHolderMessage, 'Nope');
    });
  });

  group('CardData', () {
    test('validates all three fields together', () {
      const valid = CardData(
        number: '4111 1111 1111 1111',
        expiryDate: '12/30',
        cvv: '123',
      );
      expect(valid.isValid(now: DateTime(2026, 7, 24)), isTrue);
      expect(valid.system, CardSystem.visa);

      const expired = CardData(
        number: '4111111111111111',
        expiryDate: '01/20',
        cvv: '123',
      );
      expect(expired.isValid(now: DateTime(2026, 7, 24)), isFalse);
    });

    test('never reveals the number in toString', () {
      const card = CardData(
        number: '4111111111111111',
        expiryDate: '12/30',
        cvv: '123',
      );
      expect(card.toString(), isNot(contains('4111111111111111')));
      expect(card.toString(), isNot(contains('123')));
      expect(card.masked, '411111******1111');
    });
  });

  group('Currency', () {
    test('parses codes case-insensitively', () {
      expect(Currency.fromCode('rub'), Currency.rub);
      expect(Currency.fromCode('USD'), Currency.usd);
      expect(Currency.fromCode('TRY'), Currency.tryy);
      expect(Currency.fromCode('XYZ'), isNull);
      expect(Currency.fromCode(null), isNull);
    });
  });
}
