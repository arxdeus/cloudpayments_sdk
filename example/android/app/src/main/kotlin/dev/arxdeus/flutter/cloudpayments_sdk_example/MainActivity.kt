package dev.arxdeus.flutter.cloudpayments_sdk_example

import io.flutter.embedding.android.FlutterActivity

/**
 * A stock FlutterActivity.
 *
 * Note what it does *not* do: it does not implement CloudPayments'
 * `ThreeDSDialogListener`. The plugin ships its own Activity for that, so the
 * host app has nothing to wire up.
 */
class MainActivity : FlutterActivity()
