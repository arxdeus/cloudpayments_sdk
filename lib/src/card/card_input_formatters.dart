import 'package:flutter/services.dart';

import 'card_system.dart';
import 'card_utils.dart';

/// Groups a card number as the user types — `4111 1111 1111 1111` — using the
/// grouping of the detected payment system, and caps the length at 19 digits.
///
/// The caret is kept where the user expects it: the number of digits before
/// the caret is preserved across reformatting.
class CardNumberInputFormatter extends TextInputFormatter {
  /// Creates the formatter.
  const CardNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = CardUtils.digitsOnly(newValue.text);
    final capped = digits.length > 19 ? digits.substring(0, 19) : digits;
    final formatted = CardUtils.formatNumber(capped);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _caretFor(newValue, formatted, capped.length),
      ),
    );
  }

  int _caretFor(TextEditingValue value, String formatted, int digitCount) {
    final caret = value.selection.end;
    if (caret < 0 || caret > value.text.length) return formatted.length;
    final typed = CardUtils.digitsOnly(value.text.substring(0, caret)).length;
    final digitsBeforeCaret = typed > digitCount ? digitCount : typed;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (seen == digitsBeforeCaret) return i;
      if (formatted.codeUnitAt(i) != 0x20) seen++;
    }
    return formatted.length;
  }
}

/// Formats an expiry date as `MM/yy` while typing, clamping an obviously wrong
/// leading month digit (`4` becomes `04`).
class ExpiryDateInputFormatter extends TextInputFormatter {
  /// Creates the formatter.
  const ExpiryDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = CardUtils.digitsOnly(newValue.text);
    if (digits.length > 4) digits = digits.substring(0, 4);
    // A first digit above 1 can only be a single-digit month.
    if (digits.length == 1 && int.parse(digits) > 1) digits = '0$digits';
    final formatted = CardUtils.formatExpiry(digits);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Restricts input to the digits of a security code, sized for the payment
/// system of the card number returned by [cardNumber].
class CvvInputFormatter extends TextInputFormatter {
  /// Creates the formatter. [cardNumber] is read on every keystroke so the
  /// limit follows the card the user is currently entering.
  const CvvInputFormatter({this.cardNumber});

  /// Supplies the current card number, or `null` to always allow 4 digits.
  final String Function()? cardNumber;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final number = cardNumber?.call();
    final limit = number == null || number.isEmpty
        ? 4
        : CardUtils.cvvLength(CardSystem.detect(CardUtils.digitsOnly(number)));
    var digits = CardUtils.digitsOnly(newValue.text);
    if (digits.length > limit) digits = digits.substring(0, limit);
    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}
