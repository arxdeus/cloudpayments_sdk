import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'api/cloudpayments_api_client.dart';
import 'api/cloudpayments_exception.dart';
import 'card/card_data.dart';
import 'card/card_utils.dart';
import 'form/payment_form_options.dart';
import 'form/payment_form_result.dart';
import 'models/payment_request.dart';
import 'models/payment_result.dart';
import 'models/public_key.dart';
import 'models/recurrent.dart';
import 'models/transaction.dart';
import 'platform/cloudpayments_sdk_platform.dart';
import 'platform/three_ds_result.dart';

/// The entry point of the package: card data in, paid transaction out.
///
/// ```dart
/// final cp = CloudpaymentsSdk(publicId: 'pk_xxxxxxxxxxxxxxxxxxxxxxxxx');
///
/// final result = await cp.pay(
///   card: CardData(number: '4111 1111 1111 1111', expiryDate: '12/30', cvv: '123'),
///   details: const PaymentDetails(amount: 100, invoiceId: 'ORDER-42'),
/// );
///
/// switch (result) {
///   case PaymentSuccess(:final transaction):
///     print('Paid, transaction ${transaction.transactionId}');
///   case PaymentDeclined(:final cardHolderMessage):
///     print(cardHolderMessage);
///   case PaymentCancelled():
///     print('The user closed the 3-D Secure screen');
///   case PaymentFailure(:final message):
///     print(message);
///   case PaymentRequiresThreeDs():
///     break; // pay() never returns this; it resolves the challenge itself
/// }
/// ```
///
/// [pay] runs the whole cycle: it asks the native CloudPayments SDK to encrypt
/// the card, sends the payment, opens the native 3-D Secure screen if the
/// issuer asks for it, and reports the outcome. Each step is also available on
/// its own — [createCryptogram], [api], [resolveThreeDs] — when you want to
/// drive the flow yourself.
///
/// {@macro cloudpayments_pci}
class CloudpaymentsSdk {
  /// Creates an SDK bound to one merchant account.
  ///
  /// [publicId] is the Public ID from your CloudPayments dashboard; it is not
  /// a secret and is safe to ship. Everything else is for tests and for
  /// pointing at a non-production host.
  factory CloudpaymentsSdk({
    required String publicId,
    CloudpaymentsApiClient? apiClient,
    CloudpaymentsSdkPlatform? platform,
    Uri? baseUrl,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 60),
  }) =>
      CloudpaymentsSdk._(
        publicId: publicId,
        api: apiClient ??
            CloudpaymentsApiClient(
              publicId: publicId,
              baseUrl: baseUrl,
              httpClient: httpClient,
              timeout: timeout,
            ),
        platform: platform ?? CloudpaymentsSdkPlatform.instance,
      );

  CloudpaymentsSdk._({
    required this.publicId,
    required this.api,
    required CloudpaymentsSdkPlatform platform,
  }) : _platform = platform;

  /// Your CloudPayments Public ID.
  final String publicId;

  /// The underlying REST client, for calls this class does not wrap.
  final CloudpaymentsApiClient api;

  final CloudpaymentsSdkPlatform _platform;

  CloudpaymentsPublicKey? _publicKey;
  Future<CloudpaymentsPublicKey>? _publicKeyRequest;

  // --- public key -----------------------------------------------------------

  /// The RSA key used to encrypt card data, fetched once and then cached in
  /// memory.
  ///
  /// Concurrent callers share a single request. Pass [forceRefresh] to fetch
  /// again — worth doing if a cryptogram is ever rejected as stale, since
  /// CloudPayments does rotate the key.
  Future<CloudpaymentsPublicKey> publicKey({bool forceRefresh = false}) async {
    final cached = _publicKey;
    if (!forceRefresh && cached != null) return cached;

    final inFlight = _publicKeyRequest;
    if (!forceRefresh && inFlight != null) return inFlight;

    final request = _fetchPublicKey();
    _publicKeyRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_publicKeyRequest, request)) _publicKeyRequest = null;
    }
  }

  Future<CloudpaymentsPublicKey> _fetchPublicKey() async {
    final key = await api.getPublicKey();
    _publicKey = key;
    return key;
  }

  /// Primes the public key cache.
  ///
  /// Call this when the checkout screen opens so the first payment does not
  /// pay for the round trip. Failures are swallowed — the key will simply be
  /// fetched again when it is actually needed.
  Future<void> warmUp() async {
    try {
      await publicKey();
    } on CloudpaymentsException {
      // Nothing to do: this is a best-effort optimisation.
    }
  }

  // --- cryptogram -----------------------------------------------------------

  /// Encrypts [card] into the `CardCryptogramPacket` the Payment API takes.
  ///
  /// The work happens in the official native SDK — `Card.createHexPacketFromData`
  /// on Android, `Card.makeCardCryptogramPacket` on iOS — using the RSA key
  /// from [publicKey]. Raw card data crosses the platform channel once and is
  /// retained nowhere.
  ///
  /// Throws [CloudpaymentsCryptogramException] if the card data is malformed
  /// or the native SDK refuses it.
  Future<String> createCryptogram(CardData card) async {
    final digits = CardUtils.digitsOnly(card.number);
    if (digits.length < CardUtils.minNumberLength ||
        digits.length > CardUtils.maxNumberLength) {
      throw const CloudpaymentsCryptogramException(
        'CloudPayments accepts card numbers of '
        '${CardUtils.minNumberLength} to ${CardUtils.maxNumberLength} digits.',
        code: 'invalid_card_number',
      );
    }
    if (card.cvv.isEmpty) {
      throw const CloudpaymentsCryptogramException(
        'The card security code is required.',
        code: 'invalid_cvv',
      );
    }

    final String expiry;
    try {
      expiry = CardUtils.normalizeExpiry(card.expiryDate);
    } on FormatException {
      // The date itself is card data, so it must not appear in a message that
      // may end up in a log or a crash report.
      throw const CloudpaymentsCryptogramException(
        'The card expiry date could not be read; expected MM/yy.',
        code: 'invalid_expiry_date',
      );
    }

    final key = await publicKey();
    try {
      return await _platform.createCryptogram(
        cardNumber: digits,
        expiryDate: expiry,
        cvv: card.cvv,
        publicId: publicId,
        publicKey: key.pem,
        keyVersion: key.version,
      );
    } on PlatformException catch (e) {
      throw CloudpaymentsCryptogramException(
        e.message ?? 'The native CloudPayments SDK could not encrypt the card.',
        code: e.code,
      );
    } on MissingPluginException catch (e) {
      throw CloudpaymentsCryptogramException(
        'The cloudpayments_sdk plugin is not registered on this platform. '
        'Only Android and iOS are supported. (${e.message})',
        code: 'unsupported_platform',
      );
    }
  }

  // --- the full cycle -------------------------------------------------------

  /// Runs a complete payment: encrypt, charge, authenticate if needed, report.
  ///
  /// With [twoStage] the funds are only held (`payments/cards/auth`) and the
  /// result is a transaction in `Authorized`; capture it with `confirm` or
  /// release it with `void` from your backend, both of which need the API
  /// secret.
  ///
  /// Never returns [PaymentRequiresThreeDs] — a challenge is resolved through
  /// the native screen before this future completes. The other four outcomes
  /// are all reachable.
  ///
  /// Throws [CloudpaymentsCryptogramException] for card data the native SDK
  /// rejects, [CloudpaymentsNetworkException] when CloudPayments cannot be
  /// reached, and [CloudpaymentsApiException] when the request itself is
  /// malformed. A declined card is not an exception — it comes back as
  /// [PaymentDeclined].
  Future<PaymentResult> pay({
    required CardData card,
    required PaymentDetails details,
    bool twoStage = false,
  }) async {
    final cryptogram = await createCryptogram(card);
    final request = details.asCardPayment(
      cryptogram: cryptogram,
      cardHolderName:
          card.holderName ?? CardPaymentRequest.defaultCardHolderName,
    );

    final result =
        twoStage ? await api.auth(request) : await api.charge(request);
    if (result is! PaymentRequiresThreeDs) return result;
    return resolveThreeDs(result);
  }

  /// Charges a card that has already been encrypted.
  ///
  /// Use this when you build the cryptogram yourself — for instance from an
  /// Apple Pay or Google Pay token, where the wallet's token takes the place
  /// of a card cryptogram and the cardholder name must be `Apple Pay` or
  /// `Google Pay`.
  Future<PaymentResult> payWithCryptogram({
    required String cryptogram,
    required PaymentDetails details,
    String cardHolderName = CardPaymentRequest.defaultCardHolderName,
    bool twoStage = false,
  }) async {
    final request = details.asCardPayment(
      cryptogram: cryptogram,
      cardHolderName: cardHolderName,
    );
    final result =
        twoStage ? await api.auth(request) : await api.charge(request);
    if (result is! PaymentRequiresThreeDs) return result;
    return resolveThreeDs(result);
  }

  /// Shows the native 3-D Secure screen for [pending] and finishes the payment.
  ///
  /// Call this yourself only when you drove [CloudpaymentsApiClient.charge]
  /// directly and got a [PaymentRequiresThreeDs] back; [pay] already does it.
  ///
  /// **What the result tells you.** Without an API secret the plugin finishes
  /// through `payments/ThreeDSCallback`, which answers only "did it work" —
  /// so the [PaymentSuccess.transaction] carries the transaction id but not
  /// the final amount, status or card details. Reconcile from your backend or
  /// from the CloudPayments `pay` webhook. With a secret configured (server
  /// side only) the plugin uses `payments/cards/post3ds` instead and the full
  /// transaction comes back.
  Future<PaymentResult> resolveThreeDs(PaymentRequiresThreeDs pending) async {
    final challenge = pending.challenge;

    final ThreeDsResult authentication;
    try {
      authentication = await _platform.show3ds(
        acsUrl: challenge.acsUrl,
        paReq: challenge.paReq,
        md: challenge.transactionId.toString(),
      );
    } on PlatformException catch (e) {
      return PaymentFailure(
        e.message ?? 'The 3-D Secure screen could not be opened.',
        transaction: pending.transaction,
      );
    } on MissingPluginException {
      return PaymentFailure(
        'The cloudpayments_sdk plugin is not registered on this platform, so '
        '3-D Secure cannot be shown. Only Android and iOS are supported.',
        transaction: pending.transaction,
      );
    }

    switch (authentication) {
      case ThreeDsCancelled():
        return PaymentCancelled(pending.transaction);
      case ThreeDsFailure(:final message):
        return PaymentFailure(message, transaction: pending.transaction);
      case ThreeDsSuccess(:final paRes):
        return _completeThreeDs(pending, paRes);
    }
  }

  Future<PaymentResult> _completeThreeDs(
    PaymentRequiresThreeDs pending,
    String paRes,
  ) async {
    if (paRes.isEmpty) {
      return PaymentFailure(
        'The issuer returned an empty 3-D Secure authentication response.',
        transaction: pending.transaction,
      );
    }

    final transactionId = pending.challenge.transactionId;

    // With an API secret we can use the documented endpoint, which gives back
    // the whole transaction. Apps do not have one, so they take the mobile
    // callback path.
    if (api.hasApiSecret) {
      final settled = await api.post3ds(
        transactionId: transactionId,
        paRes: paRes,
      );
      // A second challenge for a payment that has just been authenticated is
      // not something this flow can resolve, and pay() promises never to hand
      // one back. Report it rather than return an outcome the caller is told
      // cannot happen.
      if (settled is PaymentRequiresThreeDs) {
        return PaymentFailure(
          'CloudPayments asked for 3-D Secure a second time after '
          'authentication, which this package does not chain.',
          transaction: settled.transaction,
        );
      }
      return settled;
    }

    final callback = await api.completeThreeDs(
      transactionId: transactionId,
      paRes: paRes,
      threeDsCallbackId: pending.challenge.threeDsCallbackId,
    );

    if (callback.success) {
      return PaymentSuccess(
        Transaction.fromJson(<String, dynamic>{
          ...pending.transaction.raw,
          // Strip the challenge fields: they are spent, and leaving them in
          // would make the transaction look like it still needs authenticating.
          'PaReq': null,
          'AcsUrl': null,
        }),
      );
    }

    return PaymentFailure(
      callback.cardHolderMessage ??
          callback.message ??
          'The issuer did not authenticate the cardholder.',
      transaction: pending.transaction,
      reasonCode: callback.reasonCode,
    );
  }

  // --- the ready-made form --------------------------------------------------

  /// Opens CloudPayments' own payment form and resolves when it closes.
  ///
  /// This is the whole checkout in one call. The native SDK draws the UI,
  /// validates the card, runs 3-D Secure, and offers whichever of СБП, T‑Pay,
  /// SberPay, Долями and foreign cards your terminal has enabled. You do not
  /// touch [pay], [createCryptogram] or [api] — none of them are involved.
  ///
  /// ```dart
  /// final result = await cp.presentPaymentForm(
  ///   details: const PaymentDetails(
  ///     amount: 499,
  ///     accountId: 'user-42',
  ///     email: 'user@example.com',
  ///     description: 'Подписка «Про»',
  ///   ),
  ///   recurrent: const CloudpaymentsRecurrent(
  ///     interval: RecurrentInterval.month,
  ///     period: 1,
  ///   ),
  /// );
  /// ```
  ///
  /// Pass [recurrent] to create a subscription with the first payment.
  /// CloudPayments charges every following period on its own, server-side —
  /// your app is not involved again and no API secret is needed.
  ///
  /// [details]'s `ipAddress`, `cultureName`, `saveCard` and `rawCurrency` are
  /// ignored: the form fills those in itself. A [PaymentDetails.receipt] is
  /// passed to the form as a receipt rather than folded into `JsonData`, which
  /// is what the native SDKs expect.
  ///
  /// Returns [FormPaymentSucceeded], [FormPaymentFailed] or
  /// [FormPaymentClosed]. Throws [CloudpaymentsConfigurationException] if the
  /// form could not be opened at all.
  Future<PaymentFormResult> presentPaymentForm({
    required PaymentDetails details,
    CloudpaymentsRecurrent? recurrent,
    PaymentFormOptions options = const PaymentFormOptions(),
  }) async {
    final arguments = <String, dynamic>{
      'publicId': publicId,
      // The native forms take the amount as a string, like the API does.
      'amount': details.amount.toStringAsFixed(2),
      'currency': details.currencyCode,
      if (details.invoiceId != null) 'invoiceId': details.invoiceId,
      if (details.description != null) 'description': details.description,
      if (details.accountId != null) 'accountId': details.accountId,
      if (details.email != null) 'email': details.email,
      if (details.payer != null && !details.payer!.isEmpty)
        'payer': details.payer!.toJson(),
      if (details.receipt != null) 'receipt': details.receipt!.toJson(),
      if (recurrent != null) 'recurrent': recurrent.toJson(),
      if (details.jsonData != null && details.jsonData!.isNotEmpty)
        'jsonData': jsonEncode(details.jsonData),
      ...options.toArguments(),
    };

    if (recurrent != null && (details.accountId ?? '').isEmpty) {
      throw const CloudpaymentsConfigurationException(
        'A subscription needs PaymentDetails.accountId — CloudPayments binds '
        'the recurring charges to it.',
      );
    }

    final Map<Object?, Object?> answer;
    try {
      answer = await _platform.presentPaymentForm(arguments);
    } on PlatformException catch (e) {
      throw CloudpaymentsConfigurationException(
        e.message ?? 'The CloudPayments payment form could not be opened.',
      );
    } on MissingPluginException {
      throw const CloudpaymentsConfigurationException(
        'The cloudpayments_sdk plugin is not registered on this platform. '
        'The payment form is available on Android and iOS only.',
      );
    }

    int? asInt(Object? value) => switch (value) {
          final int v => v == 0 ? null : v,
          final num v => v.toInt() == 0 ? null : v.toInt(),
          final String v => int.tryParse(v),
          _ => null,
        };

    return switch (answer['status']?.toString()) {
      'succeeded' => FormPaymentSucceeded(asInt(answer['transactionId'])),
      'closed' => const FormPaymentClosed(),
      _ => FormPaymentFailed(
          transactionId: asInt(answer['transactionId']),
          reasonCode: asInt(answer['reasonCode']),
          message: answer['message']?.toString(),
        ),
    };
  }

  // --- diagnostics ----------------------------------------------------------

  /// The version of the native CloudPayments SDK the app is linked against, or
  /// `null` if the platform does not report one. For bug reports.
  Future<String?> nativeSdkVersion() async {
    try {
      return await _platform.nativeSdkVersion();
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Releases the HTTP client this SDK created. Not needed when you passed
  /// your own [CloudpaymentsApiClient] or `httpClient`.
  void dispose() => api.close();
}
