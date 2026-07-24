/// What CloudPayments knows about a card's issuing bank, looked up from the
/// first six digits of the card number.
///
/// Handy for showing the bank's name and logo in a card form while the user is
/// still typing. Nothing here is card data — a BIN identifies a bank and a
/// product, not a cardholder.
class BinInfo {
  /// Creates bank information.
  const BinInfo({required this.raw});

  /// Parses the `Model` of a `bins/info/{firstSix}` response.
  factory BinInfo.fromJson(Map<String, dynamic> json) => BinInfo(raw: json);

  /// The decoded `Model` object exactly as CloudPayments sent it.
  final Map<String, dynamic> raw;

  /// The issuing bank's name.
  String? get bankName => _string('BankName');

  /// A URL for the bank's logo.
  String? get logoUrl => _string('LogoUrl');

  /// The bank's country, as a two-letter code.
  String? get bankCountryCode => _string('BankCountryCode');

  /// Whether the card supports Cloud Payments' one-click flows.
  bool? get isCardHolderAuthRequired {
    final value = raw['IsCardHolderAuthRequired'];
    return value is bool ? value : null;
  }

  String? _string(String key) {
    final value = raw[key];
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  @override
  String toString() => 'BinInfo(bankName: $bankName)';
}
