import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloudpayments_sdk/src/api/cloudpayments_exception.dart';
import 'package:cloudpayments_sdk/src/models/bin_info.dart';
import 'package:cloudpayments_sdk/src/models/payment_request.dart';
import 'package:cloudpayments_sdk/src/models/payment_result.dart';
import 'package:cloudpayments_sdk/src/models/public_key.dart';
import 'package:cloudpayments_sdk/src/models/three_ds_callback_result.dart';
import 'package:cloudpayments_sdk/src/models/transaction.dart';
import 'package:http/http.dart' as http;

/// A typed client for the CloudPayments Payment API.
///
/// ## Two ways to authenticate
///
/// **Public ID only** (the mobile mode, and the default). This is what the
/// official iOS and Android SDKs do: the Public ID travels as a `publicId`
/// query parameter and in the request body, and no secret is involved. Only
/// the endpoints CloudPayments opens to mobile clients work in this mode:
/// [charge], [auth], [completeThreeDs], [getPublicKey] and [getBinInfo].
///
/// **Public ID + API secret** (HTTP Basic). This unlocks the whole API —
/// [confirm], [voidPayment], [refund], [getTransaction], token payments — but
/// the secret must never ship inside an app. Anyone who extracts it can move
/// money on your account. Use this mode from a server only.
///
/// Calling a secret-only method without a secret throws
/// [CloudpaymentsConfigurationException] rather than failing at the network.
class CloudpaymentsApiClient {
  /// Creates a client.
  ///
  /// [publicId] is the Public ID from your CloudPayments dashboard. Pass
  /// [apiSecret] only in server-side code — see the class docs.
  CloudpaymentsApiClient({
    required this.publicId,
    this.apiSecret,
    Uri? baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 60),
    this.sdkSource = defaultSdkSource,
    this.scenario = defaultScenario,
  })  : baseUrl = _withTrailingSlash(baseUrl ?? defaultBaseUrl),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null {
    if (publicId.isEmpty) {
      throw const CloudpaymentsConfigurationException(
        'publicId must not be empty. Copy it from '
        'https://merchant.cloudpayments.ru/.',
      );
    }
  }

  /// The production API root.
  static final Uri defaultBaseUrl = Uri.parse('https://api.cloudpayments.ru/');

  /// The value sent in the `MobileSDKSource` header, which CloudPayments uses
  /// to attribute traffic to an SDK.
  static const String defaultSdkSource =
      'Cloudpayments SDK Flutter (Custom form)';

  /// The `scenario` both official SDKs hardcode on every card payment.
  ///
  /// It is not a documented API parameter and its meaning is not published;
  /// it is sent because the native SDKs send it. [scenario] makes it
  /// overridable in case CloudPayments ever asks you to change it.
  static const int defaultScenario = 7;

  /// The URL CloudPayments redirects to after successful 3-D Secure
  /// authentication. It is a sentinel, never actually loaded.
  static const String threeDsSuccessUrl =
      'https://api.cloudpayments.ru/threeds/success';

  /// The URL CloudPayments redirects to after failed 3-D Secure
  /// authentication.
  static const String threeDsFailUrl =
      'https://api.cloudpayments.ru/threeds/fail';

  /// Your CloudPayments Public ID.
  final String publicId;

  /// Your API secret. `null` in an app; set only on a server.
  final String? apiSecret;

  /// The API root, always ending in `/`.
  ///
  /// Endpoint paths are relative, and URI resolution drops the last path
  /// segment of a base that does not end in a slash — so `https://host/api`
  /// would silently resolve to `https://host/payments/...`. The constructor
  /// appends the slash to make that impossible.
  final Uri baseUrl;

  static Uri _withTrailingSlash(Uri url) =>
      url.path.endsWith('/') ? url : url.replace(path: '${url.path}/');

  /// How long to wait for a response before giving up.
  final Duration timeout;

  /// The `MobileSDKSource` header value.
  final String sdkSource;

  /// The `scenario` value sent with card payments. See [defaultScenario].
  final int scenario;

  final http.Client _http;
  final bool _ownsClient;

  /// Whether this client can call the endpoints that need the API secret.
  bool get hasApiSecret => apiSecret != null && apiSecret!.isNotEmpty;

  // --- public key -----------------------------------------------------------

  /// Fetches the RSA public key used to encrypt card data.
  ///
  /// The native SDKs can fetch this themselves, but they do it asynchronously
  /// and cache it in platform storage, which makes the first cryptogram on a
  /// cold install fail on iOS. Fetching it here and handing it to the native
  /// side makes cryptogram creation deterministic on both platforms.
  Future<CloudpaymentsPublicKey> getPublicKey() async {
    final json = await _send('GET', 'payments/publickey');
    final key = CloudpaymentsPublicKey.fromJson(json);
    if (key.pem.isEmpty) {
      throw CloudpaymentsApiException(
        'payments/publickey returned no key',
        raw: json,
      );
    }
    return key;
  }

  // --- payments -------------------------------------------------------------

  /// Runs a one-stage payment: authorise and capture in a single step.
  ///
  /// Returns [PaymentSuccess] when the money has been taken,
  /// [PaymentRequiresThreeDs] when the issuer wants the cardholder to
  /// authenticate, or [PaymentDeclined] when the issuer refused.
  Future<PaymentResult> charge(CardPaymentRequest request) =>
      _payment('payments/cards/charge', request.toJson());

  /// Runs the first stage of a two-stage payment: hold the funds without
  /// capturing them.
  ///
  /// Capture later with [confirm], or release with [voidPayment]. Both need
  /// the API secret, so they belong on your backend.
  Future<PaymentResult> auth(CardPaymentRequest request) =>
      _payment('payments/cards/auth', request.toJson());

  /// Charges a saved card by token, in one stage.
  ///
  /// Requires the API secret — CloudPayments does not open token payments to
  /// Public ID clients. Call this from your backend.
  Future<PaymentResult> chargeToken(TokenPaymentRequest request) {
    _requireSecret('chargeToken');
    return _payment('payments/tokens/charge', request.toJson());
  }

  /// Authorises a saved card by token, without capturing.
  ///
  /// Requires the API secret. Call this from your backend.
  Future<PaymentResult> authToken(TokenPaymentRequest request) {
    _requireSecret('authToken');
    return _payment('payments/tokens/auth', request.toJson());
  }

  Future<PaymentResult> _payment(String path, Map<String, dynamic> body) async {
    final json = await _send(
      'POST',
      path,
      body: <String, dynamic>{
        ...body,
        // Both official SDKs send the Public ID in the body as well as in the
        // query string. Harmless when Basic auth is also in play.
        'PublicId': publicId,
        // Lowercase among otherwise PascalCase keys — that is how both official
        // SDKs send it, so it is reproduced verbatim.
        'scenario': scenario,
      },
    );
    return _toPaymentResult(json);
  }

  PaymentResult _toPaymentResult(Map<String, dynamic> json) {
    final success = json['Success'] == true;
    final message = json['Message'] as String?;
    final model = json['Model'];

    if (model is! Map) {
      if (success) {
        // `Success: true` and yet no transaction: the request was accepted but
        // the answer is unreadable, so the outcome is genuinely unknown.
        // Calling that a failure would be a guess in the expensive direction.
        throw CloudpaymentsNetworkException(
          'CloudPayments accepted the request but returned no transaction, so '
          'it is unknown whether the payment went through. Do not retry '
          'blindly — reconcile by InvoiceId from your backend.'
          '${message == null ? '' : ' Message: $message'}',
        );
      }
      // No transaction and no success: nothing was attempted, the request
      // itself was rejected.
      throw CloudpaymentsApiException(
        message ?? 'CloudPayments rejected the request',
        raw: json,
      );
    }

    final transaction = Transaction.fromJson(Map<String, dynamic>.from(model));
    if (success) return PaymentSuccess(transaction);

    // `Success: false` with an AcsUrl/PaReq pair is not an error — it is the
    // issuer asking for 3-D Secure. Both official SDKs branch on exactly this.
    final challenge = transaction.threeDsChallenge;
    if (challenge != null) {
      return PaymentRequiresThreeDs(challenge, transaction);
    }

    return PaymentDeclined(transaction);
  }

  // --- 3-D Secure -----------------------------------------------------------

  /// Completes a 3-D Secure payment from a mobile client.
  ///
  /// This is the `payments/ThreeDSCallback` flow both official SDKs use: it
  /// needs no API secret, but it answers only "did it work", not with a full
  /// transaction. Call it with the `md` and `paRes` the native 3-D Secure
  /// screen captured, plus the [ThreeDsChallenge.threeDsCallbackId] from the
  /// original payment response.
  ///
  /// CloudPayments answers with a redirect to a sentinel URL; this method
  /// reads the outcome from it without following it.
  Future<ThreeDsCallbackResult> completeThreeDs({
    required int transactionId,
    required String paRes,
    String? threeDsCallbackId,
    String successUrl = threeDsSuccessUrl,
    String failUrl = threeDsFailUrl,
  }) async {
    // The MD the callback endpoint expects is a JSON document, not the bare
    // transaction id that was sent to the issuer's ACS.
    final md = jsonEncode(<String, String>{
      'FailUrl': failUrl,
      'SuccessUrl': successUrl,
      'ThreeDsCallbackId': threeDsCallbackId ?? '',
      'TransactionId': transactionId.toString(),
    });

    final uri = _uri('payments/ThreeDSCallback');
    final request = http.Request('POST', uri)
      ..followRedirects = false
      ..headers.addAll(_headers())
      ..body = jsonEncode(<String, String>{'MD': md, 'PaRes': paRes});

    // One timeout around the whole exchange: a deadline on the headers alone
    // would leave a stalled body read hanging forever.
    final response = await _run(
      () => Future<http.Response>(() async {
        final streamed = await _http.send(request);
        return http.Response.fromStream(streamed);
      }).timeout(timeout),
    );

    // Preferred shape: a redirect whose target says what happened.
    final location = response.headers['location'];
    if (location != null && location.isNotEmpty) {
      final outcome = ThreeDsCallbackResult.fromRedirect(
        location,
        successUrl: successUrl,
        failUrl: failUrl,
      );
      if (!outcome.outcomeUnknown) return outcome;
      throw CloudpaymentsNetworkException(
        '${outcome.message} It is therefore unknown whether the payment went '
        'through. Do not retry blindly — reconcile transaction $transactionId '
        'from your backend.',
        statusCode: response.statusCode,
      );
    }

    // Fallbacks, because the endpoint is undocumented and the two official
    // SDKs disagree about its shape: Android types it as a bare boolean, iOS
    // as the standard envelope.
    final body = utf8.decode(response.bodyBytes).trim();
    if (body == 'true') return const ThreeDsCallbackResult(success: true);
    if (body == 'false') return const ThreeDsCallbackResult(success: false);

    final decoded = _tryDecodeObject(body);
    if (decoded != null) {
      return ThreeDsCallbackResult(
        success: decoded['Success'] == true,
        message: decoded['Message'] as String?,
      );
    }

    // Deliberately *not* "assume success on 2xx" — the Android SDK does that
    // and it is a bug: it reports paid when the response was an error page.
    // The outcome here is genuinely unknown, and saying so is the only honest
    // answer for a payment.
    throw CloudpaymentsNetworkException(
      'The 3-D Secure callback returned a response this package could not '
      'read, so it is unknown whether the payment went through. Do not retry '
      'blindly — reconcile transaction $transactionId from your backend.',
      statusCode: response.statusCode,
    );
  }

  /// Completes a 3-D Secure payment through the documented server-side
  /// endpoint, which returns the full transaction.
  ///
  /// Requires the API secret. In an app use [completeThreeDs] instead.
  Future<PaymentResult> post3ds({
    required int transactionId,
    required String paRes,
  }) async {
    _requireSecret('post3ds');
    final json = await _send(
      'POST',
      'payments/cards/post3ds',
      body: {
        'TransactionId': transactionId,
        'PaRes': paRes,
      },
    );
    return _toPaymentResult(json);
  }

  // --- transaction management (API secret required) -------------------------

  /// Captures a previously authorised payment, in full or in part.
  ///
  /// Requires the API secret. Call this from your backend.
  Future<void> confirm({
    required int transactionId,
    required num amount,
    Map<String, dynamic>? jsonData,
  }) async {
    _requireSecret('confirm');
    await _send(
      'POST',
      'payments/confirm',
      body: <String, dynamic>{
        'TransactionId': transactionId,
        'Amount': amount.toStringAsFixed(2),
        if (jsonData != null) 'JsonData': jsonEncode(jsonData),
      },
      expectSuccess: true,
    );
  }

  /// Releases a previously authorised payment without capturing it.
  ///
  /// Requires the API secret. Call this from your backend.
  Future<void> voidPayment(int transactionId) async {
    _requireSecret('voidPayment');
    await _send(
      'POST',
      'payments/void',
      body: <String, dynamic>{'TransactionId': transactionId},
      expectSuccess: true,
    );
  }

  /// Refunds a captured payment, in full or in part. Returns the id of the
  /// refund transaction CloudPayments creates.
  ///
  /// Requires the API secret. Call this from your backend.
  Future<int?> refund({
    required int transactionId,
    required num amount,
    Map<String, dynamic>? jsonData,
  }) async {
    _requireSecret('refund');
    final json = await _send(
      'POST',
      'payments/refund',
      body: <String, dynamic>{
        'TransactionId': transactionId,
        'Amount': amount.toStringAsFixed(2),
        if (jsonData != null) 'JsonData': jsonEncode(jsonData),
      },
      expectSuccess: true,
    );
    final model = json['Model'];
    if (model is Map && model['TransactionId'] != null) {
      final id = model['TransactionId'];
      return id is int ? id : int.tryParse(id.toString());
    }
    return null;
  }

  /// Looks up a transaction by id.
  ///
  /// Requires the API secret. Call this from your backend.
  Future<Transaction> getTransaction(int transactionId) async {
    _requireSecret('getTransaction');
    final json = await _send(
      'POST',
      'payments/get',
      body: <String, dynamic>{'TransactionId': transactionId},
      expectSuccess: true,
    );
    final model = json['Model'];
    if (model is! Map) {
      throw CloudpaymentsApiException(
        'payments/get returned no transaction',
        raw: json,
      );
    }
    return Transaction.fromJson(Map<String, dynamic>.from(model));
  }

  /// Checks that the credentials work. Returns the request id CloudPayments
  /// echoes back.
  ///
  /// Requires the API secret. Call this from your backend.
  Future<String?> testConnection() async {
    _requireSecret('testConnection');
    final json = await _send('POST', 'test', expectSuccess: true);
    return json['Message'] as String?;
  }

  // --- lookups --------------------------------------------------------------

  /// Looks up the issuing bank from the first six digits of a card number.
  ///
  /// Works with a Public ID alone. Useful for showing a bank logo while the
  /// user is still typing.
  Future<BinInfo?> getBinInfo(String firstSixDigits) async {
    final digits = firstSixDigits.replaceAll(RegExp('[^0-9]'), '');
    if (digits.length < 6) {
      throw const CloudpaymentsConfigurationException(
        'getBinInfo needs at least the first 6 digits of the card number',
      );
    }
    final json = await _send('GET', 'bins/info/${digits.substring(0, 6)}');
    final model = json['Model'];
    if (model is! Map) return null;
    return BinInfo.fromJson(Map<String, dynamic>.from(model));
  }

  // --- plumbing -------------------------------------------------------------

  void _requireSecret(String operation) {
    if (!hasApiSecret) {
      throw CloudpaymentsConfigurationException(
        '$operation() requires the CloudPayments API secret, which must never '
        'be shipped inside a mobile app. Call this endpoint from your backend, '
        'or construct CloudpaymentsApiClient with apiSecret in server code.',
      );
    }
  }

  Uri _uri(String path) {
    final resolved = baseUrl.resolve(path);
    return resolved.replace(
      queryParameters: <String, String>{
        ...resolved.queryParameters,
        // How the Android SDK authenticates mobile requests.
        'publicId': publicId,
      },
    );
  }

  Map<String, String> _headers() {
    final headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
      'MobileSDKSource': sdkSource,
    };
    if (hasApiSecret) {
      final credentials = base64Encode(utf8.encode('$publicId:$apiSecret'));
      headers['Authorization'] = 'Basic $credentials';
    }
    return headers;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool expectSuccess = false,
  }) async {
    final uri = _uri(path);
    final response = await _run(() {
      switch (method) {
        case 'GET':
          return _http.get(uri, headers: _headers()).timeout(timeout);
        case 'POST':
          return _http
              .post(
                uri,
                headers: _headers(),
                body: jsonEncode(body ?? const <String, dynamic>{}),
              )
              .timeout(timeout);
        default:
          throw CloudpaymentsConfigurationException(
              'Unsupported method $method');
      }
    });

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw CloudpaymentsApiException(
        'CloudPayments rejected the credentials for $path (HTTP '
        '${response.statusCode}). Check the Public ID'
        '${hasApiSecret ? ' and API secret' : ''}.',
      );
    }
    if (response.statusCode >= 500) {
      throw CloudpaymentsNetworkException(
        'CloudPayments is unavailable',
        statusCode: response.statusCode,
      );
    }

    final text = utf8.decode(response.bodyBytes);
    final json = _tryDecodeObject(text);
    if (json == null) {
      throw CloudpaymentsNetworkException(
        'CloudPayments returned a response that is not a JSON object',
        statusCode: response.statusCode,
      );
    }

    if (expectSuccess && json['Success'] != true) {
      throw CloudpaymentsApiException(
        json['Message'] as String? ?? 'CloudPayments rejected the request',
        raw: json,
      );
    }
    return json;
  }

  Map<String, dynamic>? _tryDecodeObject(String text) {
    if (text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  Future<http.Response> _run(Future<http.Response> Function() send) async {
    try {
      return await send();
    } on TimeoutException catch (e) {
      throw CloudpaymentsNetworkException(
        'CloudPayments did not answer within ${timeout.inSeconds}s',
        cause: e,
      );
    } on SocketException catch (e) {
      throw CloudpaymentsNetworkException(
        'Could not reach CloudPayments: ${e.message}',
        cause: e,
      );
    } on http.ClientException catch (e) {
      throw CloudpaymentsNetworkException(
        'Could not reach CloudPayments: ${e.message}',
        cause: e,
      );
    } on HandshakeException catch (e) {
      throw CloudpaymentsNetworkException(
        'TLS handshake with CloudPayments failed',
        cause: e,
      );
    }
  }

  /// Releases the underlying HTTP client, unless one was passed in — in that
  /// case its owner is responsible for closing it.
  void close() {
    if (_ownsClient) _http.close();
  }
}
