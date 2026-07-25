import 'package:cloudpayments_sdk/src/platform/cloudpayments_sdk_method_channel.dart';
import 'package:cloudpayments_sdk/src/platform/three_ds_result.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The interface every platform implementation of this plugin must satisfy.
///
/// Exactly two operations genuinely need native code, and only those two are
/// here:
///
/// * building a card cryptogram, which the official CloudPayments SDKs do with
///   the platform's own crypto stack, and
/// * showing the 3-D Secure screen, which must be a real platform WebView so
///   the issuer's page runs in an engine the acquirer accepts.
///
/// Everything else — validation, HTTP, orchestration — is plain Dart.
abstract class CloudpaymentsSdkPlatform extends PlatformInterface {
  /// Constructs a platform implementation.
  CloudpaymentsSdkPlatform() : super(token: _token);

  static final Object _token = Object();

  static CloudpaymentsSdkPlatform _instance = MethodChannelCloudpaymentsSdk();

  /// The implementation in use. Defaults to [MethodChannelCloudpaymentsSdk].
  static CloudpaymentsSdkPlatform get instance => _instance;

  /// Replaces the implementation in use.
  ///
  /// Platform-specific packages set this in their `registerWith()`; tests use
  /// it to swap in a fake.
  static set instance(CloudpaymentsSdkPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Encrypts card data into the `CardCryptogramPacket` the Payment API takes.
  ///
  /// [cardNumber] may contain spaces. [expiryDate] must be `MM/yy`. [cvv] is
  /// the security code, [publicId] your CloudPayments Public ID, and
  /// [publicKey]/[keyVersion] the RSA key from `payments/publickey`.
  ///
  /// Passing the key explicitly — rather than letting the native SDKs fetch
  /// and cache it themselves — is what makes this deterministic: the iOS SDK's
  /// implicit path returns `nil` until its background fetch has landed, which
  /// makes the first payment after a cold install fail.
  ///
  /// The raw card data crosses the platform channel once and is retained on
  /// neither side. Throws a `PlatformException` if the native SDK refuses it.
  Future<String> createCryptogram({
    required String cardNumber,
    required String expiryDate,
    required String cvv,
    required String publicId,
    required String publicKey,
    required int keyVersion,
  }) {
    throw UnimplementedError('createCryptogram() has not been implemented.');
  }

  /// Opens the native 3-D Secure screen and resolves once the issuer's Access
  /// Control Server has posted its result back, the user has cancelled, or
  /// authentication failed.
  ///
  /// [acsUrl] and [paReq] come from the `Model` of a payment response that
  /// needs authentication; [md] is that response's `Model.TransactionId`,
  /// which is echoed to the ACS as the merchant data field.
  Future<ThreeDsResult> show3ds({
    required String acsUrl,
    required String paReq,
    required String md,
  }) {
    throw UnimplementedError('show3ds() has not been implemented.');
  }

  /// Opens the ready-made CloudPayments payment form and resolves when it
  /// closes.
  ///
  /// The form is the native SDK's own UI — `PaymentActivity` on Android,
  /// `PaymentOptionsViewController` on iOS. It runs the entire flow itself:
  /// card entry, 3-D Secure, СБП, T‑Pay, SberPay, Долями, and creating a
  /// subscription when `recurrent` is present. Nothing in this package's
  /// low-level path is involved.
  ///
  /// [arguments] is the flattened payment plus the form options; see
  /// `PaymentFormOptions.toArguments`.
  Future<Map<Object?, Object?>> presentPaymentForm(
    Map<String, dynamic> arguments,
  ) {
    throw UnimplementedError('presentPaymentForm() has not been implemented.');
  }

  /// The version of the bundled native CloudPayments SDK, for diagnostics.
  Future<String?> nativeSdkVersion() {
    throw UnimplementedError('nativeSdkVersion() has not been implemented.');
  }
}
