/// The answer from `payments/ThreeDSCallback`, the endpoint that finishes a
/// 3-D Secure payment for clients that only have a Public ID.
///
/// CloudPayments answers with a 302 to a sentinel URL rather than with JSON:
/// the path says whether authentication succeeded, and the query string
/// carries `ReasonCode` and `CardHolderMessage`. It does not return the
/// transaction — that needs the API secret. To reconcile the payment, look it
/// up from your backend or wait for the CloudPayments `pay` webhook.
class ThreeDsCallbackResult {
  /// Creates a callback result.
  const ThreeDsCallbackResult({
    required this.success,
    this.reasonCode,
    this.cardHolderMessage,
    this.message,
    this.outcomeUnknown = false,
  });

  /// Reads the outcome from the URL CloudPayments redirects to.
  ///
  /// Matching is by prefix, which is what both official SDKs do — the sentinel
  /// URLs carry a query string that must not take part in the comparison.
  factory ThreeDsCallbackResult.fromRedirect(
    String location, {
    required String successUrl,
    required String failUrl,
  }) {
    final query = Uri.tryParse(location)?.queryParameters ?? const {};
    final reasonCode = _lookup(query, 'reasoncode');
    final cardHolderMessage = _lookup(query, 'cardholdermessage');

    if (location.startsWith(successUrl)) {
      return ThreeDsCallbackResult(
        success: true,
        reasonCode: int.tryParse(reasonCode ?? ''),
        cardHolderMessage: cardHolderMessage,
      );
    }
    if (location.startsWith(failUrl)) {
      return ThreeDsCallbackResult(
        success: false,
        reasonCode: int.tryParse(reasonCode ?? ''),
        cardHolderMessage: cardHolderMessage,
      );
    }
    // Neither sentinel matched, so the redirect says nothing about whether the
    // money moved. Reporting `success: false` here would be a guess, and the
    // wrong one is expensive in both directions.
    return ThreeDsCallbackResult(
      success: false,
      outcomeUnknown: true,
      reasonCode: int.tryParse(reasonCode ?? ''),
      cardHolderMessage: cardHolderMessage,
      message: 'CloudPayments redirected the 3-D Secure callback somewhere '
          'unexpected: $location',
    );
  }

  /// Whether the payment completed. Meaningless when [outcomeUnknown] is set.
  final bool success;

  /// Whether the answer could not be interpreted at all.
  ///
  /// When this is set, the payment may or may not have gone through — do not
  /// treat it as a failure and do not retry blindly.
  /// [CloudpaymentsApiClient.completeThreeDs] turns it into a
  /// [CloudpaymentsNetworkException] rather than let it be mistaken for one.
  final bool outcomeUnknown;

  /// The numeric reason CloudPayments gave, when the URL carried one.
  final int? reasonCode;

  /// An explanation written for the cardholder, when the URL carried one.
  /// This is the string to show in the UI.
  final String? cardHolderMessage;

  /// A description of what went wrong at the protocol level, for developers.
  final String? message;

  static String? _lookup(Map<String, String> query, String lowercaseKey) {
    for (final entry in query.entries) {
      if (entry.key.toLowerCase() == lowercaseKey) {
        return entry.value.isEmpty ? null : entry.value;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'ThreeDsCallbackResult(success: $success, reasonCode: $reasonCode)';
}
