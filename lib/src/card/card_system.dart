import 'package:meta/meta.dart';

/// Payment systems recognised by CloudPayments.
///
/// Detection is based on the card's IIN/BIN (the leading digits of the card
/// number) and is purely local — no network call is involved.
enum CardSystem {
  /// Visa.
  visa('Visa'),

  /// Mastercard.
  masterCard('MasterCard'),

  /// Maestro (Mastercard's debit brand).
  maestro('Maestro'),

  /// МИР — the Russian national payment system.
  mir('MIR'),

  /// JCB.
  jcb('JCB'),

  /// American Express.
  americanExpress('AmericanExpress'),

  /// Diners Club.
  dinersClub('DinersClub'),

  /// Discover.
  discover('Discover'),

  /// China UnionPay.
  unionPay('UnionPay'),

  /// UzCard — an Uzbek national payment system.
  uzCard('UzCard'),

  /// Humo — an Uzbek national payment system.
  humo('Humo'),

  /// Troy — the Turkish national payment system.
  troy('Troy'),

  /// The card system could not be determined from the given digits.
  unknown('Unknown');

  const CardSystem(this.wireName);

  /// The name CloudPayments uses for this system in API payloads and reports.
  final String wireName;

  /// Parses a [CardSystem] from the value CloudPayments returns in
  /// `Model.CardType`. Unrecognised values map to [CardSystem.unknown].
  @useResult
  static CardSystem fromWireName(String? name) {
    if (name == null || name.isEmpty) return CardSystem.unknown;
    final normalized = name.replaceAll(' ', '').toLowerCase();
    for (final system in CardSystem.values) {
      if (system.wireName.toLowerCase() == normalized) return system;
    }
    return CardSystem.unknown;
  }

  /// Detects the payment system from the leading digits of [digits].
  ///
  /// [digits] must already be stripped of spaces and separators. Partial
  /// numbers are supported, which is what makes this usable for live feedback
  /// while the user is still typing.
  @useResult
  static CardSystem detect(String digits) {
    if (digits.isEmpty) return CardSystem.unknown;
    for (final rule in _binRules) {
      if (rule.$1.hasMatch(digits)) return rule.$2;
    }
    return CardSystem.unknown;
  }
}

/// Ordered most-specific-first: the first pattern that matches wins, so narrow
/// ranges (Maestro's `6759`, MIR's `220x`) must precede broad ones (`6…`).
final List<(RegExp, CardSystem)> _binRules = <(RegExp, CardSystem)>[
  (RegExp('^220[0-4]'), CardSystem.mir),
  (RegExp('^9792'), CardSystem.troy),
  (RegExp('^8600'), CardSystem.uzCard),
  (RegExp('^9860'), CardSystem.humo),
  (
    RegExp('^(5018|5020|5038|5893|6304|6759|676[1-3]|0604|6390|5[6-8])'),
    CardSystem.maestro,
  ),
  (RegExp('^4'), CardSystem.visa),
  (
    RegExp('^(5[1-5]|222[1-9]|22[3-9][0-9]|2[3-6][0-9]{2}|27[01][0-9]|2720)'),
    CardSystem.masterCard,
  ),
  (RegExp('^3[47]'), CardSystem.americanExpress),
  (RegExp('^(2131|1800|35)'), CardSystem.jcb),
  (RegExp('^3(0[0-5]|[68][0-9])'), CardSystem.dinersClub),
  (RegExp('^(6011|64[4-9]|65)'), CardSystem.discover),
  (RegExp('^62'), CardSystem.unionPay),
];
