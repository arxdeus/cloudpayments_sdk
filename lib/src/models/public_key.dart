import 'package:meta/meta.dart';

/// The RSA public key CloudPayments issues for encrypting card data, together
/// with the version the gateway needs in order to pick the matching private
/// key.
///
/// Fetch it with [CloudpaymentsApiClient.getPublicKey]. It rotates rarely, so
/// caching it for the lifetime of the app is fine — [CloudpaymentsSdk] does
/// exactly that.
@immutable
class CloudpaymentsPublicKey {
  /// Creates a key.
  const CloudpaymentsPublicKey({required this.pem, required this.version});

  /// Parses the `payments/publickey` response.
  factory CloudpaymentsPublicKey.fromJson(Map<String, dynamic> json) {
    final version = json['Version'];
    return CloudpaymentsPublicKey(
      pem: json['Pem'] as String? ?? '',
      version: switch (version) {
        final int v => v,
        final num v => v.toInt(),
        final String v => int.tryParse(v) ?? 0,
        _ => 0,
      },
    );
  }

  /// The key in PEM form, exactly as CloudPayments returns it — including the
  /// `-----BEGIN PUBLIC KEY-----` armour, which the native SDKs strip
  /// themselves.
  final String pem;

  /// The key version. It is sent alongside the cryptogram so the gateway knows
  /// which private key to decrypt with.
  final int version;

  @override
  String toString() => 'CloudpaymentsPublicKey(version: $version)';
}
