import 'dart:convert';

import 'currency.dart';
import 'payer.dart';
import 'receipt.dart';
import 'recurrent.dart';

/// Everything about a payment except *how* it is paid for.
///
/// Build one of these and hand it to [CloudpaymentsSdk.pay], or turn it into a
/// concrete request with [asCardPayment] / [asTokenPayment] when driving the
/// API client directly.
///
/// Field names on the wire are PascalCase (`Amount`, `InvoiceId`) exactly as
/// CloudPayments expects; the Dart names are idiomatic.
class PaymentDetails {
  /// Creates payment details.
  const PaymentDetails({
    required this.amount,
    this.currency = Currency.rub,
    this.rawCurrency,
    this.invoiceId,
    this.description,
    this.accountId,
    this.email,
    this.ipAddress,
    this.payer,
    this.jsonData,
    this.receipt,
    this.recurrent,
    this.cultureName,
    this.saveCard,
  });

  /// The amount to charge, in [currency].
  ///
  /// Serialised with two decimal places, which is what both official SDKs
  /// send. Amounts with more precision than that are rounded.
  final num amount;

  /// The currency. Defaults to [Currency.rub], matching the API default.
  final Currency currency;

  /// An ISO 4217 code to send instead of [currency], for currencies this
  /// package does not enumerate.
  final String? rawCurrency;

  /// Your order number.
  final String? invoiceId;

  /// A free-form payment description shown to the cardholder.
  final String? description;

  /// Your identifier for the paying user. Required to save a card, and to
  /// charge a saved token later.
  final String? accountId;

  /// Where to send the payment receipt.
  final String? email;

  /// The cardholder's IP address, used for fraud scoring and geolocation.
  ///
  /// CloudPayments documents this as required for cryptogram payments. A
  /// mobile client cannot discover its own public address, so get it from your
  /// backend — for example, have your API echo the caller's address back.
  final String? ipAddress;

  /// Structured payer details, used for fraud scoring and 3-D Secure 2
  /// frictionless flows.
  final Payer? payer;

  /// Arbitrary data to attach to the transaction, serialised into the
  /// `JsonData` string. Merged with [receipt] when both are given.
  final Map<String, dynamic>? jsonData;

  /// A fiscal receipt to register with the payment (54-ФЗ). Folded into
  /// `JsonData` under `CloudPayments.CustomerReceipt`.
  final Receipt? receipt;

  /// Instructions to create a subscription with this payment. Folded into
  /// `JsonData` under `CloudPayments.recurrent`.
  ///
  /// CloudPayments charges every following period itself, so nothing else is
  /// needed from the app. [accountId] must be set.
  ///
  /// With the ready-made form, pass the subscription to
  /// [CloudpaymentsSdk.presentPaymentForm] instead — the native SDKs have a
  /// dedicated field for it there.
  final CloudpaymentsRecurrent? recurrent;

  /// The language of cardholder-facing messages and notification emails.
  final CultureName? cultureName;

  /// Ask CloudPayments to save the card and return a `Token` in the response.
  /// Requires [accountId].
  final bool? saveCard;

  /// The currency code that goes on the wire.
  String get currencyCode => rawCurrency ?? currency.code;

  /// The combined `JsonData` payload, or `null` when there is nothing to send.
  ///
  /// A receipt and a subscription both live under the same `CloudPayments`
  /// wrapper, alongside whatever else [jsonData] carries.
  Map<String, dynamic>? get effectiveJsonData {
    var data = jsonData;
    if (receipt != null) data = receipt!.toJsonData(data);
    if (recurrent != null) {
      final merged = <String, dynamic>{...?data};
      merged['CloudPayments'] = <String, dynamic>{
        ...?(merged['CloudPayments'] as Map<String, dynamic>?),
        'recurrent': recurrent!.toJson(),
      };
      data = merged;
    }
    return data;
  }

  /// Pairs these details with a card cryptogram.
  CardPaymentRequest asCardPayment({
    required String cryptogram,
    String cardHolderName = CardPaymentRequest.defaultCardHolderName,
  }) =>
      CardPaymentRequest(
        amount: amount,
        cryptogram: cryptogram,
        cardHolderName: cardHolderName,
        currency: currency,
        rawCurrency: rawCurrency,
        invoiceId: invoiceId,
        description: description,
        accountId: accountId,
        email: email,
        ipAddress: ipAddress,
        payer: payer,
        jsonData: jsonData,
        receipt: receipt,
        recurrent: recurrent,
        cultureName: cultureName,
        saveCard: saveCard,
      );

  /// Pairs these details with a saved-card token.
  ///
  /// [accountId] must be set — CloudPayments requires it for token payments.
  TokenPaymentRequest asTokenPayment(String token) {
    final id = accountId;
    if (id == null || id.isEmpty) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'A token payment requires the accountId the card was saved under',
      );
    }
    return TokenPaymentRequest(
      amount: amount,
      token: token,
      accountId: id,
      currency: currency,
      rawCurrency: rawCurrency,
      invoiceId: invoiceId,
      description: description,
      email: email,
      ipAddress: ipAddress,
      payer: payer,
      jsonData: jsonData,
      receipt: receipt,
      cultureName: cultureName,
    );
  }

  /// Serialises the fields shared by every payment request.
  Map<String, dynamic> toJson() {
    final data = effectiveJsonData;
    return <String, dynamic>{
      'Amount': amount.toStringAsFixed(2),
      'Currency': currencyCode,
      if (ipAddress != null) 'IpAddress': ipAddress,
      if (invoiceId != null) 'InvoiceId': invoiceId,
      if (description != null) 'Description': description,
      if (accountId != null) 'AccountId': accountId,
      if (email != null) 'Email': email,
      if (payer != null && !payer!.isEmpty) 'Payer': payer!.toJson(),
      if (data != null && data.isNotEmpty) 'JsonData': jsonEncode(data),
      if (cultureName != null) 'CultureName': cultureName!.code,
      if (saveCard != null) 'SaveCard': saveCard,
    };
  }
}

/// A payment made with card data that has been encrypted into a cryptogram.
///
/// You will rarely build one by hand — [CloudpaymentsSdk.pay] does it for you.
/// Use it directly when you want to drive the flow step by step.
class CardPaymentRequest extends PaymentDetails {
  /// Creates a card payment request.
  const CardPaymentRequest({
    required super.amount,
    required this.cryptogram,
    this.cardHolderName = defaultCardHolderName,
    super.currency,
    super.rawCurrency,
    super.invoiceId,
    super.description,
    super.accountId,
    super.email,
    super.ipAddress,
    super.payer,
    super.jsonData,
    super.receipt,
    super.recurrent,
    super.cultureName,
    super.saveCard,
  });

  /// What the official SDKs send when the cardholder name is unknown. The
  /// field is required by the API but is not checked against the card.
  static const String defaultCardHolderName = 'Cloudpayments SDK';

  /// The name to send for a Google Pay token payment.
  static const String googlePayCardHolderName = 'Google Pay';

  /// The name to send for an Apple Pay token payment.
  static const String applePayCardHolderName = 'Apple Pay';

  /// The `CardCryptogramPacket` produced by the native SDK.
  final String cryptogram;

  /// The cardholder name, in Latin characters.
  final String cardHolderName;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...super.toJson(),
        'Name': cardHolderName,
        'CardCryptogramPacket': cryptogram,
      };
}

/// A repeat payment against a card token from an earlier payment made with
/// `saveCard: true`.
///
/// Token payments are **not** open to Public ID clients — CloudPayments
/// requires the API secret, so they must run on your backend. The model lives
/// here so you can share it between app and server code.
class TokenPaymentRequest extends PaymentDetails {
  /// Creates a token payment request. [accountId] is required by the API.
  const TokenPaymentRequest({
    required super.amount,
    required this.token,
    required String super.accountId,
    super.currency,
    super.rawCurrency,
    super.invoiceId,
    super.description,
    super.email,
    super.ipAddress,
    super.payer,
    super.jsonData,
    super.receipt,
    super.recurrent,
    super.cultureName,
  });

  /// The saved-card token from a previous transaction's `Model.Token`.
  final String token;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        ...super.toJson(),
        'Token': token,
      };
}
