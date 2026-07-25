import 'package:meta/meta.dart';

/// The outcome of the ready-made CloudPayments payment form.
///
/// The form owns the whole flow — card entry, 3-D Secure, СБП, T‑Pay and the
/// rest — so what comes back is deliberately small: it happened, it didn't, or
/// the user walked away.
///
/// ```dart
/// final result = await cp.presentPaymentForm(details: details);
/// switch (result) {
///   case FormPaymentSucceeded(:final transactionId):
///     print('Оплачено, транзакция $transactionId');
///   case FormPaymentFailed(:final reasonCode):
///     print('Не прошло, код $reasonCode');
///   case FormPaymentClosed():
///     print('Пользователь закрыл форму');
/// }
/// ```
///
/// To get the full transaction, look it up from your backend or handle the
/// CloudPayments `pay` webhook — the form does not return one, and fetching it
/// needs the API secret.
@immutable
sealed class PaymentFormResult {
  const PaymentFormResult();

  /// The transaction the form ended on, when it got that far.
  int? get transactionId;

  /// Whether the payment went through.
  bool get isSuccess => this is FormPaymentSucceeded;
}

/// The payment succeeded.
///
/// With `twoStage` the funds are held rather than captured, and the
/// transaction is `Authorized` — capture it with `confirm` from your backend.
final class FormPaymentSucceeded extends PaymentFormResult {
  /// Creates a successful outcome.
  const FormPaymentSucceeded(this.transactionId);

  @override
  final int? transactionId;

  @override
  String toString() => 'FormPaymentSucceeded($transactionId)';
}

/// The payment did not go through — declined, or failed somewhere in the form.
final class FormPaymentFailed extends PaymentFormResult {
  /// Creates a failed outcome.
  const FormPaymentFailed({this.transactionId, this.reasonCode, this.message});

  @override
  final int? transactionId;

  /// CloudPayments' numeric reason, e.g. `5051` for insufficient funds. Zero
  /// or `null` when the form did not report one.
  final int? reasonCode;

  /// What the native SDK said went wrong, when it said anything. iOS reports
  /// a message; Android reports only a reason code.
  final String? message;

  @override
  String toString() =>
      'FormPaymentFailed(transactionId: $transactionId, reasonCode: $reasonCode)';
}

/// The user closed the form without paying. No money moved.
final class FormPaymentClosed extends PaymentFormResult {
  /// Creates a dismissal outcome.
  const FormPaymentClosed();

  @override
  int? get transactionId => null;

  @override
  String toString() => 'FormPaymentClosed()';
}
