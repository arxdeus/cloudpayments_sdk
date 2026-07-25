import 'package:meta/meta.dart';

/// The payment methods the ready-made form can offer.
///
/// Which ones actually appear depends on what is enabled for your terminal in
/// the CloudPayments dashboard — listing one here does not switch it on.
enum CloudpaymentsPaymentMethod {
  /// A bank card.
  card('Card'),

  /// A card issued outside Russia.
  foreignCard('ForeignCard'),

  /// T‑Pay (formerly Tinkoff Pay).
  tPay('TinkoffPay'),

  /// SberPay.
  sberPay('SberPay'),

  /// СБП — the Fast Payments System.
  sbp('Sbp'),

  /// Долями (buy now, pay later).
  dolyame('Dolyame');

  const CloudpaymentsPaymentMethod(this.wireName);

  /// The identifier the native SDKs use.
  ///
  /// Verified against the iOS `PaymentMethodType` enum. The Android SDK takes
  /// the same strings in a list; if one is not recognised there it only
  /// affects the display order, never whether a payment can be made.
  final String wireName;
}

/// How the form treats the email field.
enum EmailFieldBehavior {
  /// Shown, and the user can turn it off.
  optional('OPTIONAL'),

  /// Shown and must be filled in.
  required('REQUIRED'),

  /// Not shown at all.
  hidden('HIDDEN');

  const EmailFieldBehavior(this.wireName);

  /// The identifier passed to the native SDKs.
  final String wireName;
}

/// Options for the ready-made CloudPayments payment form.
///
/// Everything here is optional; the defaults give the standard form with the
/// method-selection screen.
///
/// A few settings only exist on one platform. They are all in one class rather
/// than split in two because that is how you will use them — the ignored ones
/// simply do nothing on the other platform, and each says so below.
@immutable
class PaymentFormOptions {
  /// Creates form options.
  const PaymentFormOptions({
    this.twoStage = false,
    this.emailBehavior = EmailFieldBehavior.optional,
    this.methodOrder = const [],
    this.singleMethod,
    this.showResultScreen = true,
    this.testMode = false,
    this.saveCardInSingleMethodMode,
    this.disableApplePay = true,
    this.successRedirectUrl,
    this.failRedirectUrl,
  });

  /// Hold the funds instead of capturing them (two-stage payment).
  ///
  /// Capturing later needs the API secret, so it happens on your backend.
  final bool twoStage;

  /// How the form treats the email field.
  final EmailFieldBehavior emailBehavior;

  /// The order payment methods appear in. Methods you leave out still appear,
  /// after the ones you list.
  final List<CloudpaymentsPaymentMethod> methodOrder;

  /// Skip the method-selection screen and go straight to this one.
  ///
  /// If the method is not enabled for your terminal, the SDK reports a
  /// configuration error instead.
  final CloudpaymentsPaymentMethod? singleMethod;

  /// Whether the form shows its own success/failure screen at the end.
  ///
  /// Only has an effect together with [singleMethod]; otherwise the form
  /// always shows its result screen.
  final bool showResultScreen;

  /// Run the form against the CloudPayments test gateway. **Android only** —
  /// on iOS test mode follows the Public ID you use.
  final bool testMode;

  /// Offer to save the card when [singleMethod] is set. **Android only.**
  final bool? saveCardInSingleMethodMode;

  /// Hide Apple Pay. **iOS only**, and defaults to hidden: Apple Pay needs a
  /// merchant identifier and entitlements this package does not configure.
  final bool disableApplePay;

  /// Universal Link the bank app returns to after a successful payment.
  /// **iOS only**, and only relevant for СБП, T‑Pay, SberPay and Долями.
  final String? successRedirectUrl;

  /// Universal Link the bank app returns to after a failed payment.
  /// **iOS only.**
  final String? failRedirectUrl;

  /// Serialises the options for the platform channel.
  @useResult
  Map<String, dynamic> toArguments() => <String, dynamic>{
        'twoStage': twoStage,
        'emailBehavior': emailBehavior.wireName,
        'methodOrder': methodOrder.map((m) => m.wireName).toList(),
        if (singleMethod != null) 'singleMethod': singleMethod!.wireName,
        'showResultScreen': showResultScreen,
        'testMode': testMode,
        if (saveCardInSingleMethodMode != null)
          'saveCardInSingleMethodMode': saveCardInSingleMethodMode,
        'disableApplePay': disableApplePay,
        if (successRedirectUrl != null)
          'successRedirectUrl': successRedirectUrl,
        if (failRedirectUrl != null) 'failRedirectUrl': failRedirectUrl,
      };
}
