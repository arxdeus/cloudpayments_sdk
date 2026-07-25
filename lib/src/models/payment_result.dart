import 'package:meta/meta.dart';

import 'transaction.dart';

/// The outcome of a payment.
///
/// Business outcomes are values, not exceptions: a declined card and a
/// cancelled 3-D Secure screen are things that happen, not errors. `switch`
/// over this is exhaustive, so the compiler will tell you when you have missed
/// a case.
///
/// ```dart
/// final result = await sdk.pay(...);
/// final message = switch (result) {
///   PaymentSuccess(:final transaction) => 'Paid #${transaction.transactionId}',
///   PaymentDeclined(:final cardHolderMessage) => cardHolderMessage,
///   PaymentCancelled() => 'Cancelled',
///   PaymentFailure(:final message) => message,
///   PaymentRequiresThreeDs() => 'Authentication required',
/// };
/// ```
@immutable
sealed class PaymentResult {
  const PaymentResult();

  /// The transaction this outcome refers to, when there is one.
  Transaction? get transaction;

  /// Whether the money was taken (or authorised, for a two-stage payment).
  bool get isSuccess => this is PaymentSuccess;
}

/// The payment went through.
///
/// For a one-stage payment the funds are captured and
/// [Transaction.status] is `Completed`. For a two-stage payment they are held
/// and the status is `Authorized` — capture them with `confirm` from your
/// backend, or release them with `void`.
final class PaymentSuccess extends PaymentResult {
  /// Creates a successful outcome.
  const PaymentSuccess(this.transaction);

  @override
  final Transaction transaction;

  /// The saved-card token, present when the payment was made with
  /// `saveCard: true`.
  String? get token => transaction.token;

  @override
  String toString() => 'PaymentSuccess(${transaction.transactionId})';
}

/// The issuer wants the cardholder to authenticate before the payment can go
/// ahead.
///
/// Only the low-level [CloudpaymentsApiClient] returns this.
/// [CloudpaymentsSdk.pay] resolves the challenge itself and never gives you
/// one to handle.
final class PaymentRequiresThreeDs extends PaymentResult {
  /// Creates a pending-authentication outcome.
  const PaymentRequiresThreeDs(this.challenge, this.transaction);

  /// Everything the native 3-D Secure screen needs.
  final ThreeDsChallenge challenge;

  @override
  final Transaction transaction;

  @override
  String toString() => 'PaymentRequiresThreeDs(${challenge.transactionId})';
}

/// The issuer refused the payment.
///
/// Show [cardHolderMessage] — CloudPayments localises it to the request's
/// `CultureName` and writes it for cardholders. [reasonCode] is the machine
/// readable reason, e.g. `5051` for insufficient funds.
final class PaymentDeclined extends PaymentResult {
  /// Creates a declined outcome.
  const PaymentDeclined(this.transaction);

  @override
  final Transaction transaction;

  /// A decline explanation written for the cardholder.
  String? get cardHolderMessage => transaction.cardHolderMessage;

  /// The numeric decline reason.
  int? get reasonCode => transaction.reasonCode;

  /// The decline reason in English, e.g. `InsufficientFunds`.
  String? get reason => transaction.reason;

  @override
  String toString() =>
      'PaymentDeclined(${transaction.transactionId}, $reasonCode $reason)';
}

/// The cardholder dismissed the 3-D Secure screen without finishing.
///
/// The transaction stays in `AwaitingAuthentication` and no money moves.
/// Treat this as "changed their mind", not as a failure to report.
final class PaymentCancelled extends PaymentResult {
  /// Creates a cancelled outcome, optionally carrying the transaction that
  /// was awaiting authentication.
  const PaymentCancelled([this.transaction]);

  @override
  final Transaction? transaction;

  @override
  String toString() => 'PaymentCancelled()';
}

/// The payment could not be completed for a reason that is neither a decline
/// nor a cancellation — most often 3-D Secure authentication that failed.
final class PaymentFailure extends PaymentResult {
  /// Creates a failed outcome.
  const PaymentFailure(this.message, {this.transaction, this.reasonCode});

  /// What went wrong.
  final String message;

  @override
  final Transaction? transaction;

  /// The numeric reason CloudPayments gave, when there was one.
  final int? reasonCode;

  @override
  String toString() => 'PaymentFailure($message)';
}
