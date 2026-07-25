import 'package:cloudpayments_sdk/src/card/card_system.dart';
import 'package:meta/meta.dart';

/// The lifecycle state of a transaction, as reported in `Model.Status`.
enum TransactionStatus {
  /// The payment is waiting for the cardholder to pass 3-D Secure.
  awaitingAuthentication('AwaitingAuthentication'),

  /// The funds are held but not yet captured — the result of a two-stage
  /// `auth`. Capture with `confirm`, release with `void`.
  authorized('Authorized'),

  /// The funds have been captured. This is the terminal success state.
  completed('Completed'),

  /// The authorisation was released without capture.
  cancelled('Cancelled'),

  /// The issuer or CloudPayments refused the payment.
  declined('Declined'),

  /// A status this package does not know about. Read
  /// [Transaction.rawStatus] for the original string.
  unknown('Unknown');

  const TransactionStatus(this.wireName);

  /// The exact string CloudPayments sends in `Model.Status`.
  final String wireName;

  /// Parses `Model.Status`, case-insensitively.
  @useResult
  static TransactionStatus fromWireName(String? name) {
    if (name == null || name.isEmpty) return TransactionStatus.unknown;
    for (final status in TransactionStatus.values) {
      if (status.wireName.toLowerCase() == name.toLowerCase()) return status;
    }
    return TransactionStatus.unknown;
  }
}

/// The 3-D Secure challenge a transaction is waiting on.
///
/// CloudPayments signals "authentication required" with `Success: false`,
/// `Message: null` and an `AcsUrl`/`PaReq` pair in the `Model` — it is not an
/// error. Hand this object to the native 3-D Secure screen.
@immutable
class ThreeDsChallenge {
  /// Creates a challenge descriptor.
  const ThreeDsChallenge({
    required this.transactionId,
    required this.acsUrl,
    required this.paReq,
    this.threeDsCallbackId,
    this.threeDsSessionData,
    this.goReq,
    this.iFrameIsAllowed,
    this.frameWidth,
    this.frameHeight,
  });

  /// The transaction being authenticated. Sent to the ACS as `MD`.
  final int transactionId;

  /// The issuer's Access Control Server page to POST to.
  final String acsUrl;

  /// The authentication request payload to POST to [acsUrl].
  final String paReq;

  /// The identifier CloudPayments needs to match the callback back to this
  /// payment. Required when completing the payment.
  final String? threeDsCallbackId;

  /// 3-D Secure 2 session data, when the ACS uses it.
  final String? threeDsSessionData;

  /// The 3-D Secure 2 counterpart of [paReq], when present.
  final String? goReq;

  /// Whether the ACS page may be shown in an iframe.
  final bool? iFrameIsAllowed;

  /// Suggested frame width for the ACS page.
  final int? frameWidth;

  /// Suggested frame height for the ACS page.
  final int? frameHeight;

  @override
  String toString() =>
      'ThreeDsChallenge(transactionId: $transactionId, acsUrl: $acsUrl)';
}

/// A CloudPayments transaction — the `Model` object of a payment response.
///
/// Only the fields the API documents are surfaced as typed getters; anything
/// else CloudPayments returns is still available through [raw].
@immutable
class Transaction {
  /// Creates a transaction. You will normally get one from the API rather
  /// than build it yourself.
  const Transaction({required this.raw});

  /// Parses a `Model` object.
  factory Transaction.fromJson(Map<String, dynamic> json) =>
      Transaction(raw: json);

  /// The decoded `Model` object exactly as CloudPayments sent it.
  final Map<String, dynamic> raw;

  // --- identity -------------------------------------------------------------

  /// The CloudPayments transaction number.
  int? get transactionId => _int('TransactionId');

  /// Your order number, echoed back.
  String? get invoiceId => _string('InvoiceId');

  /// Your user identifier, echoed back. Required to charge a saved [token].
  String? get accountId => _string('AccountId');

  /// The payment description, echoed back.
  String? get description => _string('Description');

  /// The cardholder's email.
  String? get email => _string('Email');

  /// The cardholder name as it was submitted.
  String? get name => _string('Name');

  /// Arbitrary data attached to the payment, as a JSON string.
  String? get jsonData => _string('JsonData');

  /// Whether the payment ran against the test gateway.
  bool? get testMode => _bool('TestMode');

  // --- money ----------------------------------------------------------------

  /// The transaction amount.
  num? get amount => _num('Amount');

  /// The transaction currency code, e.g. `RUB`.
  String? get currency => _string('Currency');

  /// The numeric currency code.
  int? get currencyCode => _int('CurrencyCode');

  /// The amount actually taken from the card, when it differs from [amount].
  num? get paymentAmount => _num('PaymentAmount');

  /// The currency actually charged, when it differs from [currency].
  String? get paymentCurrency => _string('PaymentCurrency');

  /// The total fee CloudPayments charged for the transaction.
  num? get totalFee => _num('TotalFee');

  // --- status ---------------------------------------------------------------

  /// The lifecycle state of the transaction.
  TransactionStatus get status => TransactionStatus.fromWireName(rawStatus);

  /// The raw `Model.Status` string, including values this package does not
  /// model.
  String? get rawStatus => _string('Status');

  /// The numeric status code that accompanies [status].
  int? get statusCode => _int('StatusCode');

  /// The decline reason in English, e.g. `InsufficientFunds`.
  String? get reason => _string('Reason');

  /// The numeric decline reason, e.g. `5051`.
  int? get reasonCode => _int('ReasonCode');

  /// A decline explanation written for the cardholder, localised to the
  /// request's `CultureName`. Show this rather than [reason].
  String? get cardHolderMessage => _string('CardHolderMessage');

  /// Whether the payment succeeded outright — captured, or authorised and
  /// awaiting capture.
  bool get isSuccessful =>
      status == TransactionStatus.completed ||
      status == TransactionStatus.authorized;

  /// Whether the payment was declined.
  bool get isDeclined => status == TransactionStatus.declined;

  // --- card -----------------------------------------------------------------

  /// The card's first six digits (its BIN).
  String? get cardFirstSix => _string('CardFirstSix');

  /// The card's last four digits.
  String? get cardLastFour => _string('CardLastFour');

  /// The card's expiry date as `MM/yy`.
  String? get cardExpDate => _string('CardExpDate');

  /// The card's payment system as CloudPayments reports it.
  CardSystem get cardSystem => CardSystem.fromWireName(_string('CardType'));

  /// The raw `Model.CardType` string.
  String? get cardType => _string('CardType');

  /// The numeric card type code.
  int? get cardTypeCode => _int('CardTypeCode');

  /// The issuing bank's name.
  String? get issuer => _string('Issuer');

  /// The issuing bank's two-letter country code.
  String? get issuerBankCountry => _string('IssuerBankCountry');

  /// A masked rendering of the card, e.g. `411111******1111`.
  String? get maskedCard {
    final first = cardFirstSix;
    final last = cardLastFour;
    if (first == null || last == null) return null;
    return '$first******$last';
  }

  /// The token for charging this card again without asking for its details.
  /// Present only when the payment was made with `SaveCard: true` or the
  /// merchant account saves cards by default.
  String? get token => _string('Token');

  // --- authorisation --------------------------------------------------------

  /// The issuer's authorisation code.
  String? get authCode => _string('AuthCode');

  /// When the payment was authorised, as an ISO 8601 string.
  String? get authDateIso => _string('AuthDateIso');

  /// When the payment was captured, as an ISO 8601 string.
  String? get confirmDateIso => _string('ConfirmDateIso');

  /// When the transaction was created, as an ISO 8601 string.
  String? get createdDateIso => _string('CreatedDateIso');

  /// [createdDateIso] parsed, or `null` if absent or unparseable.
  DateTime? get createdDate => _dateTime('CreatedDateIso');

  /// [authDateIso] parsed, or `null` if absent or unparseable.
  DateTime? get authDate => _dateTime('AuthDateIso');

  /// [confirmDateIso] parsed, or `null` if absent or unparseable.
  DateTime? get confirmDate => _dateTime('ConfirmDateIso');

  /// The retrieval reference number.
  String? get rrn => _string('Rrn');

  /// The subscription this payment belongs to, when it is a recurring charge.
  String? get subscriptionId => _string('SubscriptionId');

  // --- geo ------------------------------------------------------------------

  /// The IP address the payment was made from.
  String? get ipAddress => _string('IpAddress');

  /// The country the IP address resolves to.
  String? get ipCountry => _string('IpCountry');

  /// The city the IP address resolves to.
  String? get ipCity => _string('IpCity');

  /// The region the IP address resolves to.
  String? get ipRegion => _string('IpRegion');

  /// The district the IP address resolves to.
  String? get ipDistrict => _string('IpDistrict');

  // --- 3-D Secure -----------------------------------------------------------

  /// The ACS page to send the cardholder to for authentication.
  String? get acsUrl => _string('AcsUrl');

  /// The 3-D Secure 1 authentication request.
  String? get paReq => _string('PaReq');

  /// The 3-D Secure 2 authentication request.
  String? get goReq => _string('GoReq');

  /// The identifier CloudPayments uses to match a 3-D Secure callback back to
  /// this payment.
  String? get threeDsCallbackId => _string('ThreeDsCallbackId');

  /// 3-D Secure 2 session data.
  String? get threeDsSessionData => _string('ThreeDsSessionData');

  /// Whether the payment is waiting for 3-D Secure authentication.
  ///
  /// This mirrors what the official SDKs check: an `AcsUrl` and a `PaReq` were
  /// both returned.
  bool get requiresThreeDs =>
      (acsUrl?.isNotEmpty ?? false) && (paReq?.isNotEmpty ?? false);

  /// The pending 3-D Secure challenge, or `null` when none is required.
  ThreeDsChallenge? get threeDsChallenge {
    if (!requiresThreeDs) return null;
    final id = transactionId;
    if (id == null) return null;
    return ThreeDsChallenge(
      transactionId: id,
      acsUrl: acsUrl!,
      paReq: paReq!,
      threeDsCallbackId: threeDsCallbackId,
      threeDsSessionData: threeDsSessionData,
      goReq: goReq,
      iFrameIsAllowed: _bool('IFrameIsAllowed'),
      frameWidth: _int('FrameWidth'),
      frameHeight: _int('FrameHeight'),
    );
  }

  // --- parsing helpers ------------------------------------------------------

  String? _string(String key) {
    final value = raw[key];
    if (value == null) return null;
    final text = value is String ? value : value.toString();
    return text.isEmpty ? null : text;
  }

  int? _int(String key) {
    final value = raw[key];
    return switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v),
      _ => null,
    };
  }

  num? _num(String key) {
    final value = raw[key];
    return switch (value) {
      final num v => v,
      final String v => num.tryParse(v.replaceAll(',', '.')),
      _ => null,
    };
  }

  bool? _bool(String key) {
    final value = raw[key];
    return switch (value) {
      final bool v => v,
      'true' || 'True' => true,
      'false' || 'False' => false,
      _ => null,
    };
  }

  DateTime? _dateTime(String key) {
    final value = _string(key);
    return value == null ? null : DateTime.tryParse(value);
  }

  @override
  String toString() => 'Transaction(id: $transactionId, status: $rawStatus, '
      'amount: $amount $currency, card: $maskedCard)';
}
