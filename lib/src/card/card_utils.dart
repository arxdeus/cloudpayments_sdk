import 'package:cloudpayments_sdk/src/card/card_system.dart';
import 'package:meta/meta.dart';

/// Pure-Dart validation, detection and formatting helpers for card data.
///
/// Everything here runs locally — nothing is sent anywhere and nothing is
/// cached. Use it to drive live feedback in a card form before handing the
/// card off to `CloudpaymentsSdk.createCryptogram`, which is the only place
/// the raw PAN leaves Dart.
///
/// {@template cloudpayments_pci}
/// **PCI DSS note.** Raw card data must never be logged, persisted, or sent to
/// your own backend. Keep it in memory only for as long as it takes to build a
/// cryptogram, then drop it.
/// {@endtemplate}
abstract final class CardUtils {
  /// Strips every character that is not a decimal digit.
  @useResult
  static String digitsOnly(String input) =>
      input.replaceAll(RegExp('[^0-9]'), '');

  /// Detects the payment system of [number]. Tolerates partial input and any
  /// separators.
  @useResult
  static CardSystem detectSystem(String number) =>
      CardSystem.detect(digitsOnly(number));

  /// The shortest card number CloudPayments will process.
  ///
  /// Both native SDKs refuse anything shorter, so a 13-digit Visa — valid in
  /// the abstract — cannot be charged here. [isValidNumber] applies the same
  /// floor, so a number this library calls valid is one the payment path can
  /// actually use.
  static const int minNumberLength = 14;

  /// The longest card number CloudPayments will process.
  static const int maxNumberLength = 19;

  /// Card number lengths accepted for [system], shortest first.
  ///
  /// Never below [minNumberLength] — see its documentation.
  @useResult
  static List<int> allowedLengths(CardSystem system) => switch (system) {
        CardSystem.visa => const [16, 18, 19],
        CardSystem.masterCard => const [16],
        CardSystem.maestro => const [14, 15, 16, 17, 18, 19],
        CardSystem.mir => const [16, 18, 19],
        CardSystem.americanExpress => const [15],
        CardSystem.dinersClub => const [14, 16, 19],
        CardSystem.discover => const [16, 19],
        CardSystem.jcb => const [16, 17, 18, 19],
        CardSystem.unionPay => const [16, 17, 18, 19],
        CardSystem.uzCard || CardSystem.humo => const [16],
        CardSystem.troy => const [16],
        CardSystem.unknown => const [14, 15, 16, 17, 18, 19],
      };

  /// The length of the security code for [system]: 4 for American Express,
  /// 3 for everything else.
  @useResult
  static int cvvLength(CardSystem system) =>
      system == CardSystem.americanExpress ? 4 : 3;

  /// Whether [digits] satisfies the Luhn checksum.
  ///
  /// Returns `false` for an empty string or for any non-digit input.
  @useResult
  static bool passesLuhn(String digits) {
    if (digits.isEmpty) return false;
    var sum = 0;
    var doubling = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      final code = digits.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) return false;
      var value = code - 0x30;
      if (doubling) {
        value *= 2;
        if (value > 9) value -= 9;
      }
      sum += value;
      doubling = !doubling;
    }
    return sum % 10 == 0;
  }

  /// Validates a card number: a length CloudPayments accepts for the detected
  /// system, and a valid Luhn checksum.
  ///
  /// UzCard and Humo numbers are exempt from the Luhn check — those national
  /// systems do not use a Luhn check digit.
  @useResult
  static bool isValidNumber(String number) {
    final digits = digitsOnly(number);
    if (digits.length < minNumberLength || digits.length > maxNumberLength) {
      return false;
    }
    final system = CardSystem.detect(digits);
    if (!allowedLengths(system).contains(digits.length)) return false;
    if (system == CardSystem.uzCard || system == CardSystem.humo) return true;
    return passesLuhn(digits);
  }

  /// Validates a security code against the detected system of [cardNumber].
  ///
  /// When [cardNumber] is omitted, any 3- or 4-digit code is accepted.
  @useResult
  static bool isValidCvv(String cvv, {String? cardNumber}) {
    final digits = digitsOnly(cvv);
    if (digits.length != cvv.length) return false;
    if (cardNumber == null || cardNumber.isEmpty) {
      return digits.length == 3 || digits.length == 4;
    }
    return digits.length == cvvLength(detectSystem(cardNumber));
  }

  /// Parses an expiry date into its `(month, year)` parts, where `year` is the
  /// full four-digit year. Returns `null` when [expiry] is not a well-formed
  /// `MM/YY`, `MMYY`, `MM/YYYY` or `MMYYYY` value with a month in 1..12.
  @useResult
  static (int month, int year)? parseExpiry(String expiry) {
    final digits = digitsOnly(expiry);
    if (digits.length != 4 && digits.length != 6) return null;
    final month = int.tryParse(digits.substring(0, 2));
    if (month == null || month < 1 || month > 12) return null;
    final yearPart = int.tryParse(digits.substring(2));
    if (yearPart == null) return null;
    final year = digits.length == 4 ? 2000 + yearPart : yearPart;
    if (year < 2000 || year > 2100) return null;
    return (month, year);
  }

  /// Whether [expiry] is well-formed and has not yet passed.
  ///
  /// A card is valid through the final day of its expiry month. [now] exists
  /// for tests; it defaults to the current local time.
  @useResult
  static bool isValidExpiryDate(String expiry, {DateTime? now}) {
    final parsed = parseExpiry(expiry);
    if (parsed == null) return false;
    final (month, year) = parsed;
    final today = now ?? DateTime.now();
    // The first instant of the month *after* the expiry month.
    final expiresAt = DateTime(year, month + 1);
    return today.isBefore(expiresAt);
  }

  /// Normalises an expiry date to the `MM/yy` form the CloudPayments SDKs
  /// expect when building a cryptogram.
  ///
  /// Throws [FormatException] if [expiry] cannot be parsed.
  @useResult
  static String normalizeExpiry(String expiry) {
    final parsed = parseExpiry(expiry);
    if (parsed == null) {
      throw FormatException('Not a valid card expiry date', expiry);
    }
    final (month, year) = parsed;
    final mm = month.toString().padLeft(2, '0');
    final yy = (year % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }

  /// Digit-group sizes used when rendering a number of the given [system].
  @useResult
  static List<int> groupSizes(CardSystem system) => switch (system) {
        CardSystem.americanExpress => const [4, 6, 5],
        CardSystem.dinersClub => const [4, 6, 4],
        _ => const [4, 4, 4, 4, 4],
      };

  /// Formats a card number for display, e.g. `4111 1111 1111 1111`.
  ///
  /// Works on partial input, so it can be applied on every keystroke.
  @useResult
  static String formatNumber(String number) {
    final digits = digitsOnly(number);
    if (digits.isEmpty) return '';
    final groups = groupSizes(CardSystem.detect(digits));
    final buffer = StringBuffer();
    var index = 0;
    var group = 0;
    while (index < digits.length) {
      if (index > 0) buffer.write(' ');
      final size = group < groups.length ? groups[group] : 4;
      final end = (index + size) > digits.length ? digits.length : index + size;
      buffer.write(digits.substring(index, end));
      index = end;
      group++;
    }
    return buffer.toString();
  }

  /// Formats a partially typed expiry date as `MM/yy`.
  @useResult
  static String formatExpiry(String input) {
    final digits = digitsOnly(input);
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return digits;
    final month = digits.substring(0, 2);
    final year = digits.substring(2, digits.length > 4 ? 4 : digits.length);
    return '$month/$year';
  }

  /// Masks a card number to the PCI-safe `first 6 … last 4` form, e.g.
  /// `411111******1111`.
  ///
  /// Numbers too short to mask meaningfully are returned fully masked.
  @useResult
  static String maskNumber(String number) {
    final digits = digitsOnly(number);
    if (digits.length < 12) return '*' * digits.length;
    final head = digits.substring(0, 6);
    final tail = digits.substring(digits.length - 4);
    final hidden = '*' * (digits.length - 10);
    return '$head$hidden$tail';
  }
}
