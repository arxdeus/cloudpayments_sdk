import 'package:cloudpayments_sdk/src/platform/cloudpayments_sdk_platform.dart';
import 'package:cloudpayments_sdk/src/platform/three_ds_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The default [CloudpaymentsSdkPlatform], talking to the Android and iOS
/// implementations over a [MethodChannel].
class MethodChannelCloudpaymentsSdk extends CloudpaymentsSdkPlatform {
  /// The channel shared with the native side. Its name is part of the plugin's
  /// contract — changing it means changing both platforms too.
  @visibleForTesting
  final MethodChannel methodChannel =
      const MethodChannel('dev.arxdeus.flutter/cloudpayments_sdk');

  @override
  Future<String> createCryptogram({
    required String cardNumber,
    required String expiryDate,
    required String cvv,
    required String publicId,
    required String publicKey,
    required int keyVersion,
  }) async {
    final cryptogram = await methodChannel.invokeMethod<String>(
      'createCryptogram',
      <String, dynamic>{
        'cardNumber': cardNumber,
        'expiryDate': expiryDate,
        'cvv': cvv,
        'publicId': publicId,
        'publicKey': publicKey,
        'keyVersion': keyVersion,
      },
    );
    if (cryptogram == null || cryptogram.isEmpty) {
      throw PlatformException(
        code: 'cryptogram_failed',
        message: 'The native CloudPayments SDK returned an empty cryptogram.',
      );
    }
    return cryptogram;
  }

  @override
  Future<ThreeDsResult> show3ds({
    required String acsUrl,
    required String paReq,
    required String md,
  }) async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'show3ds',
      <String, dynamic>{
        'acsUrl': acsUrl,
        'paReq': paReq,
        'md': md,
      },
    );
    if (result == null) return const ThreeDsCancelled();
    return switch (result['status']?.toString()) {
      'success' => ThreeDsSuccess.fromMap(result),
      'cancelled' => const ThreeDsCancelled(),
      _ => ThreeDsFailure.fromMap(result),
    };
  }

  @override
  Future<Map<Object?, Object?>> presentPaymentForm(
    Map<String, dynamic> arguments,
  ) async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'presentPaymentForm',
      arguments,
    );
    // A null answer can only mean the screen went away without reporting.
    return result ?? const <Object?, Object?>{'status': 'closed'};
  }

  @override
  Future<String?> nativeSdkVersion() =>
      methodChannel.invokeMethod<String>('nativeSdkVersion');
}
