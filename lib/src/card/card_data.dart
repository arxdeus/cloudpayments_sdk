import 'card_system.dart';
import 'card_utils.dart';

/// Raw card details, on their way to being encrypted.
///
/// {@macro cloudpayments_pci}
///
/// An instance is meant to live for the duration of one payment. It
/// deliberately does not implement `==`, `hashCode` or a revealing
/// `toString()`, so it cannot leak into logs, crash reports or a widget tree
/// diff by accident.
class CardData {
  /// Creates card details.
  ///
  /// [number] may be formatted with spaces; [expiryDate] may be `MM/yy`,
  /// `MMyy`, `MM/yyyy` or `MMyyyy`.
  const CardData({
    required this.number,
    required this.expiryDate,
    required this.cvv,
    this.holderName,
  });

  /// The primary account number.
  final String number;

  /// The expiry date.
  final String expiryDate;

  /// The security code (CVV / CVC / CVP).
  final String cvv;

  /// The cardholder name in Latin characters, as printed on the card.
  ///
  /// CloudPayments requires a `Name` on every card payment but does not check
  /// it; when this is `null` the SDK sends the same placeholder the official
  /// SDKs use.
  final String? holderName;

  /// The card's payment system.
  CardSystem get system => CardUtils.detectSystem(number);

  /// Whether the number, expiry date and security code are all well formed.
  ///
  /// [now] exists for tests; it defaults to the current local time.
  bool isValid({DateTime? now}) =>
      CardUtils.isValidNumber(number) &&
      CardUtils.isValidExpiryDate(expiryDate, now: now) &&
      CardUtils.isValidCvv(cvv, cardNumber: number);

  /// A PCI-safe rendering, e.g. `411111******1111`. This is the only
  /// representation of a card that is safe to log.
  String get masked => CardUtils.maskNumber(number);

  @override
  String toString() => 'CardData($masked, ${system.wireName})';
}
