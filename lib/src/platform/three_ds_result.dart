import 'package:meta/meta.dart';

/// The outcome of the native 3-D Secure screen.
///
/// The screen is a WebView hosted by the platform — an `Activity` on Android,
/// a presented `UIViewController` on iOS — that loads the issuer's Access
/// Control Server page and captures the result it posts back. Exactly one of
/// the three subclasses comes back, so `switch` over them is exhaustive.
@immutable
sealed class ThreeDsResult {
  const ThreeDsResult();
}

/// The cardholder completed authentication and the ACS posted its result back.
///
/// Feed [md] and [paRes] into `payments/ThreeDSCallback` (or the server-side
/// `payments/cards/post3ds`) to finish the payment.
class ThreeDsSuccess extends ThreeDsResult {
  /// Creates a successful authentication result.
  const ThreeDsSuccess({required this.md, required this.paRes});

  /// Restores the result from the map sent over the method channel.
  factory ThreeDsSuccess.fromMap(Map<Object?, Object?> map) => ThreeDsSuccess(
        md: map['md']?.toString() ?? '',
        paRes: map['paRes']?.toString() ?? '',
      );

  /// The merchant data echoed back by the ACS — for CloudPayments, the
  /// `TransactionId` of the payment being authenticated.
  final String md;

  /// The authentication response, to be sent back to CloudPayments.
  final String paRes;

  @override
  String toString() => 'ThreeDsSuccess(md: $md)';
}

/// Authentication failed: the ACS returned something other than a valid
/// callback, or the issuer refused the challenge.
class ThreeDsFailure extends ThreeDsResult {
  /// Creates a failed authentication result.
  const ThreeDsFailure({required this.message, this.html});

  /// Restores the result from the map sent over the method channel.
  factory ThreeDsFailure.fromMap(Map<Object?, Object?> map) => ThreeDsFailure(
        message:
            map['message']?.toString() ?? '3-D Secure authentication failed',
        html: map['html']?.toString(),
      );

  /// What went wrong.
  final String message;

  /// The raw body the ACS returned. Useful in a bug report; never show it to
  /// the user and never log it in production — it can carry card metadata.
  final String? html;

  @override
  String toString() => 'ThreeDsFailure($message)';
}

/// The user dismissed the 3-D Secure screen before finishing.
class ThreeDsCancelled extends ThreeDsResult {
  /// Creates a cancellation result.
  const ThreeDsCancelled();

  @override
  String toString() => 'ThreeDsCancelled()';
}
