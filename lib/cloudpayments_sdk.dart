/// CloudPayments for Flutter.
///
/// Card validation and formatting in pure Dart, cryptogram generation through
/// the official CloudPayments native SDKs, the Payment API over HTTPS, and
/// 3-D Secure in a native WebView screen.
///
/// Start with [CloudpaymentsSdk]:
///
/// ```dart
/// final cp = CloudpaymentsSdk(publicId: 'pk_xxxxxxxxxxxxxxxxxxxxxxxxx');
/// final result = await cp.pay(
///   card: CardData(number: '4111111111111111', expiryDate: '12/30', cvv: '123'),
///   details: const PaymentDetails(amount: 100, currency: Currency.rub),
/// );
/// ```
///
/// Card data must never be logged, persisted, or sent anywhere other than
/// through [CloudpaymentsSdk.createCryptogram]. Keep it in memory only for as
/// long as it takes to build a cryptogram.
library;

export 'src/api/cloudpayments_api_client.dart';
export 'src/api/cloudpayments_exception.dart';
export 'src/card/card_data.dart';
export 'src/card/card_input_formatters.dart';
export 'src/card/card_system.dart';
export 'src/card/card_utils.dart';
export 'src/cloudpayments_sdk_base.dart';
export 'src/form/payment_form_options.dart';
export 'src/form/payment_form_result.dart';
export 'src/models/bin_info.dart';
export 'src/models/currency.dart';
export 'src/models/payer.dart';
export 'src/models/payment_request.dart';
export 'src/models/payment_result.dart';
export 'src/models/public_key.dart';
export 'src/models/receipt.dart';
export 'src/models/recurrent.dart';
export 'src/models/three_ds_callback_result.dart';
export 'src/models/transaction.dart';
export 'src/platform/cloudpayments_sdk_method_channel.dart';
export 'src/platform/cloudpayments_sdk_platform.dart';
export 'src/platform/three_ds_result.dart';
