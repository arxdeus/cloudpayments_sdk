import 'package:meta/meta.dart';

/// Base class for the failures this package throws.
///
/// Only *errors* are exceptions here. A declined card, a failed 3-D Secure
/// challenge and a user who cancelled are ordinary outcomes of a payment, so
/// they come back as a [PaymentResult] instead of being thrown.
///
/// The class is `sealed`, so a `switch` over it is checked for exhaustiveness:
///
/// ```dart
/// try {
///   await sdk.pay(...);
/// } on CloudpaymentsException catch (e) {
///   final text = switch (e) {
///     CloudpaymentsNetworkException() => 'No connection, try again',
///     CloudpaymentsCryptogramException() => 'Check the card details',
///     _ => e.message,
///   };
/// }
/// ```
@immutable
sealed class CloudpaymentsException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const CloudpaymentsException(this.message);

  /// A description of what went wrong, written for a developer. Do not show it
  /// to a cardholder.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The package was used incorrectly — `pay()` before `init()`, an empty Public
/// ID, a request that needs the API secret when only a Public ID is set, and
/// so on. These are programming errors; they should not reach production.
class CloudpaymentsConfigurationException extends CloudpaymentsException {
  /// Creates a configuration error.
  const CloudpaymentsConfigurationException(super.message);
}

/// The request never reached CloudPayments, or the response could not be read:
/// no connectivity, a timeout, a TLS failure, a 5xx, or a non-JSON body.
///
/// Retrying is usually reasonable. A payment that timed out may still have
/// gone through — reconcile by `InvoiceId` rather than blindly retrying the
/// charge.
class CloudpaymentsNetworkException extends CloudpaymentsException {
  /// Creates a transport-level error.
  const CloudpaymentsNetworkException(
    super.message, {
    this.statusCode,
    this.cause,
  });

  /// The HTTP status code, when a response did arrive.
  final int? statusCode;

  /// The underlying error, e.g. a `SocketException` or `TimeoutException`.
  final Object? cause;

  @override
  String toString() => 'CloudpaymentsNetworkException: $message'
      '${statusCode != null ? ' (HTTP $statusCode)' : ''}';
}

/// CloudPayments rejected the *request itself* — `Success: false` with a
/// `Message` and no transaction: a bad Public ID, a missing amount, a
/// malformed cryptogram. No payment was attempted.
class CloudpaymentsApiException extends CloudpaymentsException {
  /// Creates an API-level error.
  const CloudpaymentsApiException(super.message, {this.raw});

  /// The decoded response body, for diagnostics.
  final Map<String, dynamic>? raw;
}

/// The native SDK could not build a card cryptogram.
///
/// The usual causes are card data the native validator rejects (CloudPayments
/// accepts card numbers of 14 to 19 digits only) or a public key that could
/// not be fetched.
class CloudpaymentsCryptogramException extends CloudpaymentsException {
  /// Creates a cryptogram failure.
  const CloudpaymentsCryptogramException(super.message, {this.code});

  /// The platform error code from the native side, when there was one.
  final String? code;
}
