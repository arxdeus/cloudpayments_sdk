import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('digitsOnly', () {
    test('strips separators and letters', () {
      expect(CardUtils.digitsOnly('4111 1111-1111_1111'), '4111111111111111');
      expect(CardUtils.digitsOnly('abc'), '');
      expect(CardUtils.digitsOnly(''), '');
    });
  });

  group('detectSystem', () {
    const cases = <String, CardSystem>{
      '4111111111111111': CardSystem.visa,
      '4': CardSystem.visa,
      '5555555555554444': CardSystem.masterCard,
      '2223003122003222': CardSystem.masterCard,
      '2200000000000053': CardSystem.mir,
      '378282246310005': CardSystem.americanExpress,
      '371449635398431': CardSystem.americanExpress,
      '30569309025904': CardSystem.dinersClub,
      '6011111111111117': CardSystem.discover,
      '3530111333300000': CardSystem.jcb,
      '6250947000000014': CardSystem.unionPay,
      '6759649826438453': CardSystem.maestro,
      '8600123456789012': CardSystem.uzCard,
      '9860123456789012': CardSystem.humo,
      '9792123456789012': CardSystem.troy,
      '': CardSystem.unknown,
      '7000000000000000': CardSystem.unknown,
    };

    cases.forEach((number, expected) {
      test('detects ${expected.wireName} from "$number"', () {
        expect(CardUtils.detectSystem(number), expected);
      });
    });

    test('works on partial input as the user types', () {
      expect(CardUtils.detectSystem('22'), CardSystem.unknown);
      expect(CardUtils.detectSystem('2200'), CardSystem.mir);
      expect(CardUtils.detectSystem('2201'), CardSystem.mir);
      expect(CardUtils.detectSystem('2221'), CardSystem.masterCard);
    });

    test('tolerates formatting separators', () {
      expect(CardUtils.detectSystem('4111 1111'), CardSystem.visa);
    });
  });

  group('fromWireName', () {
    test('parses names the API returns', () {
      expect(CardSystem.fromWireName('Visa'), CardSystem.visa);
      expect(CardSystem.fromWireName('MasterCard'), CardSystem.masterCard);
      expect(CardSystem.fromWireName('MIR'), CardSystem.mir);
      expect(
        CardSystem.fromWireName('American Express'),
        CardSystem.americanExpress,
      );
      expect(CardSystem.fromWireName(null), CardSystem.unknown);
      expect(CardSystem.fromWireName('Frobnicator'), CardSystem.unknown);
    });
  });

  group('passesLuhn', () {
    test('accepts valid checksums', () {
      expect(CardUtils.passesLuhn('4111111111111111'), isTrue);
      expect(CardUtils.passesLuhn('378282246310005'), isTrue);
      expect(CardUtils.passesLuhn('2200000000000053'), isTrue);
    });

    test('rejects invalid checksums, empty and non-digit input', () {
      expect(CardUtils.passesLuhn('4111111111111112'), isFalse);
      expect(CardUtils.passesLuhn(''), isFalse);
      expect(CardUtils.passesLuhn('4111 1111'), isFalse);
    });
  });

  group('isValidNumber', () {
    test('accepts well-formed numbers of every supported system', () {
      for (final number in const [
        '4111111111111111',
        '4242424242424242',
        '5555555555554444',
        '5105105105105100',
        '2223003122003222',
        '2200000000000053',
        '378282246310005',
        '30569309025904',
        '6011111111111117',
        '3530111333300000',
        '6250947000000014',
        '6759649826438453',
      ]) {
        expect(CardUtils.isValidNumber(number), isTrue, reason: number);
      }
    });

    test('accepts formatted input', () {
      expect(CardUtils.isValidNumber('4111 1111 1111 1111'), isTrue);
    });

    test('rejects a bad checksum', () {
      expect(CardUtils.isValidNumber('4111111111111112'), isFalse);
    });

    test('rejects a length the system does not allow', () {
      // American Express is 15 digits; a 16th digit makes it invalid whatever
      // the checksum says.
      expect(CardUtils.isValidNumber('3782822463100051'), isFalse);
    });

    test('rejects too short and too long', () {
      expect(CardUtils.isValidNumber('41111'), isFalse);
      expect(CardUtils.isValidNumber('41111111111111111111'), isFalse);
      expect(CardUtils.isValidNumber(''), isFalse);
    });

    test('exempts UzCard and Humo from the Luhn check', () {
      expect(CardUtils.isValidNumber('8600123456789012'), isTrue);
      expect(CardUtils.isValidNumber('9860123456789012'), isTrue);
    });
  });

  group('isValidCvv', () {
    test('requires 3 digits for most systems', () {
      expect(
        CardUtils.isValidCvv('123', cardNumber: '4111111111111111'),
        isTrue,
      );
      expect(
        CardUtils.isValidCvv('1234', cardNumber: '4111111111111111'),
        isFalse,
      );
      expect(
        CardUtils.isValidCvv('12', cardNumber: '4111111111111111'),
        isFalse,
      );
    });

    test('requires 4 digits for American Express', () {
      expect(
        CardUtils.isValidCvv('1234', cardNumber: '378282246310005'),
        isTrue,
      );
      expect(
        CardUtils.isValidCvv('123', cardNumber: '378282246310005'),
        isFalse,
      );
    });

    test('accepts 3 or 4 digits when the card number is unknown', () {
      expect(CardUtils.isValidCvv('123'), isTrue);
      expect(CardUtils.isValidCvv('1234'), isTrue);
      expect(CardUtils.isValidCvv('12345'), isFalse);
    });

    test('rejects non-digits', () {
      expect(CardUtils.isValidCvv('12a'), isFalse);
      expect(CardUtils.isValidCvv(''), isFalse);
    });
  });

  group('parseExpiry', () {
    test('parses the accepted forms', () {
      expect(CardUtils.parseExpiry('12/25'), (12, 2025));
      expect(CardUtils.parseExpiry('1225'), (12, 2025));
      expect(CardUtils.parseExpiry('12/2025'), (12, 2025));
      expect(CardUtils.parseExpiry('122025'), (12, 2025));
      expect(CardUtils.parseExpiry('01/30'), (1, 2030));
    });

    test('rejects malformed input', () {
      expect(CardUtils.parseExpiry('13/25'), isNull);
      expect(CardUtils.parseExpiry('00/25'), isNull);
      expect(CardUtils.parseExpiry('1/25'), isNull);
      expect(CardUtils.parseExpiry(''), isNull);
      expect(CardUtils.parseExpiry('12/1999'), isNull);
    });
  });

  group('isValidExpiryDate', () {
    final now = DateTime(2026, 7, 24);

    test('a card is valid through the last day of its expiry month', () {
      expect(CardUtils.isValidExpiryDate('07/26', now: now), isTrue);
      expect(
        CardUtils.isValidExpiryDate('07/26', now: DateTime(2026, 7, 31, 23)),
        isTrue,
      );
      expect(CardUtils.isValidExpiryDate('08/26', now: now), isTrue);
    });

    test('rejects a month that has passed', () {
      expect(CardUtils.isValidExpiryDate('06/26', now: now), isFalse);
      expect(CardUtils.isValidExpiryDate('12/25', now: now), isFalse);
    });

    test('rejects malformed input', () {
      expect(CardUtils.isValidExpiryDate('13/30', now: now), isFalse);
      expect(CardUtils.isValidExpiryDate('nope', now: now), isFalse);
    });
  });

  group('normalizeExpiry', () {
    test('normalises to MM/yy', () {
      expect(CardUtils.normalizeExpiry('1225'), '12/25');
      expect(CardUtils.normalizeExpiry('12/2025'), '12/25');
      expect(CardUtils.normalizeExpiry('01/30'), '01/30');
    });

    test('throws on malformed input', () {
      expect(
        () => CardUtils.normalizeExpiry('99/99'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('formatNumber', () {
    test('groups in fours by default', () {
      expect(
        CardUtils.formatNumber('4111111111111111'),
        '4111 1111 1111 1111',
      );
      expect(CardUtils.formatNumber('41111'), '4111 1');
      expect(CardUtils.formatNumber(''), '');
    });

    test('uses 4-6-5 for American Express', () {
      expect(CardUtils.formatNumber('378282246310005'), '3782 822463 10005');
    });

    test('uses 4-6-4 for Diners Club', () {
      expect(CardUtils.formatNumber('30569309025904'), '3056 930902 5904');
    });

    test('handles 19-digit numbers', () {
      expect(
        CardUtils.formatNumber('4111111111111111111'),
        '4111 1111 1111 1111 111',
      );
    });
  });

  group('formatExpiry', () {
    test('inserts the slash after the month', () {
      expect(CardUtils.formatExpiry('1'), '1');
      expect(CardUtils.formatExpiry('12'), '12');
      expect(CardUtils.formatExpiry('122'), '12/2');
      expect(CardUtils.formatExpiry('1225'), '12/25');
      expect(CardUtils.formatExpiry('12255'), '12/25');
      expect(CardUtils.formatExpiry(''), '');
    });
  });

  group('maskNumber', () {
    test('keeps the first six and last four digits', () {
      expect(CardUtils.maskNumber('4111111111111111'), '411111******1111');
      expect(CardUtils.maskNumber('378282246310005'), '378282*****0005');
    });

    test('fully masks numbers too short to reveal safely', () {
      expect(CardUtils.maskNumber('41111'), '*****');
    });
  });
}
