# The CloudPayments SDK ships its own consumer ProGuard rules, so nothing extra
# is needed for it. These rules cover this plugin's own entry points, which are
# reached reflectively by the Android framework rather than from Kotlin code.

-keep class dev.arxdeus.flutter.cloudpayments_sdk.CloudpaymentsSdkPlugin { *; }
-keep class dev.arxdeus.flutter.cloudpayments_sdk.CloudpaymentsThreeDsActivity { *; }
