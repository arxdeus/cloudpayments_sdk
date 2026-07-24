import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Applies [formatter] to [text] as if the user had just typed it, with the
/// caret at [caret] (end of text by default).
TextEditingValue _type(
  TextInputFormatter formatter,
  String text, {
  int? caret,
  String previous = '',
}) =>
    formatter.formatEditUpdate(
      TextEditingValue(
        text: previous,
        selection: TextSelection.collapsed(offset: previous.length),
      ),
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret ?? text.length),
      ),
    );

void main() {
  group('CardNumberInputFormatter', () {
    const formatter = CardNumberInputFormatter();

    test('groups digits as they are typed', () {
      expect(_type(formatter, '4111').text, '4111');
      expect(_type(formatter, '41111').text, '4111 1');
      expect(_type(formatter, '4111111111111111').text, '4111 1111 1111 1111');
    });

    test('regroups for American Express', () {
      expect(_type(formatter, '378282246310005').text, '3782 822463 10005');
    });

    test('drops anything that is not a digit', () {
      expect(_type(formatter, '4111-abc-1111').text, '4111 1111');
    });

    test('stops at 19 digits', () {
      final result = _type(formatter, '4' * 25);
      expect(CardUtils.digitsOnly(result.text).length, 19);
    });

    test('keeps the caret after the digit the user just typed', () {
      // Caret sits after the fourth digit; the formatter inserts a space at
      // that position, and the caret must not jump past it.
      final result = _type(formatter, '41111', caret: 4, previous: '4111');
      expect(result.text, '4111 1');
      expect(result.selection.baseOffset, 4);
    });

    test('puts the caret at the end when there is no usable selection', () {
      final result = formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '4111111111111111'),
      );
      expect(result.selection.baseOffset, result.text.length);
    });

    test('leaves an empty field empty', () {
      expect(_type(formatter, '').text, '');
    });
  });

  group('ExpiryDateInputFormatter', () {
    const formatter = ExpiryDateInputFormatter();

    test('inserts the slash after the month', () {
      expect(_type(formatter, '1').text, '1');
      expect(_type(formatter, '12').text, '12');
      expect(_type(formatter, '123').text, '12/3');
      expect(_type(formatter, '1230').text, '12/30');
    });

    test('pads a month that can only be single-digit', () {
      // A leading 4 cannot start a month, so it must mean April. The slash
      // waits until a year digit follows.
      expect(_type(formatter, '4').text, '04');
      expect(_type(formatter, '2').text, '02');
      // The field now holds "04"; the next keystroke appends to that.
      expect(_type(formatter, '043', previous: '04').text, '04/3');
      // A leading 1 is still ambiguous — January or October, November,
      // December — so it is left alone.
      expect(_type(formatter, '1').text, '1');
    });

    test('stops at four digits', () {
      expect(_type(formatter, '1230999').text, '12/30');
    });

    test('leaves an empty field empty', () {
      expect(_type(formatter, '').text, '');
    });
  });

  group('CvvInputFormatter', () {
    test('allows three digits for most systems', () {
      final formatter = CvvInputFormatter(cardNumber: () => '4111111111111111');
      expect(_type(formatter, '123').text, '123');
      expect(_type(formatter, '1234').text, '123');
    });

    test('allows four for American Express', () {
      final formatter = CvvInputFormatter(cardNumber: () => '378282246310005');
      expect(_type(formatter, '1234').text, '1234');
      expect(_type(formatter, '12345').text, '1234');
    });

    test('allows four when the card number is not known yet', () {
      const formatter = CvvInputFormatter();
      expect(_type(formatter, '1234').text, '1234');
      expect(_type(formatter, '12345').text, '1234');
    });

    test('follows the card the user is currently editing', () {
      var number = '';
      final formatter = CvvInputFormatter(cardNumber: () => number);

      number = '378282246310005';
      expect(_type(formatter, '1234').text, '1234');

      number = '4111111111111111';
      expect(_type(formatter, '1234').text, '123');
    });

    test('drops anything that is not a digit', () {
      const formatter = CvvInputFormatter();
      expect(_type(formatter, '1a2').text, '12');
    });
  });
}
