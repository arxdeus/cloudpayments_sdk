# cloudpayments_sdk example

A one-screen checkout that runs the full CloudPayments cycle: card entry with
live validation, cryptogram, charge, 3-D Secure, result.

## Running it

```bash
cd example
flutter pub get
flutter run
```

### Android

The runner is complete and should build as-is. Two settings differ from a stock
`flutter create` app, both required by the CloudPayments SDK and both already
applied in `android/app/build.gradle`:

- `minSdk = 24`, `compileSdk` 37 and Java/Kotlin target 17. API 37 is published
  only as `platforms;android-37.0`, so the compile SDK is declared through
  `release(37) { minorApiLevel = 0 }` and the app needs AGP 8.13 or newer.
- `manifestPlaceholders["cpSdkHost"] = ""` — without it the manifest merger
  fails, because the SDK's own manifest declares a deep-link host through that
  placeholder. Add to the map rather than assigning it, or Flutter's own
  `applicationName` placeholder is dropped and the merge fails anyway.

`android/build.gradle` also adds the JitPack repository, which is the only place
the CloudPayments Android SDK is published.

### iOS

The runner builds as-is. `ios/Runner.xcodeproj` is checked in with every
`IPHONEOS_DEPLOYMENT_TARGET` already at **15.0**, which CloudPayments requires
and Flutter's template does not default to.

Do not regenerate it with `flutter create --platforms=ios .` — that resets the
deployment target to Flutter's default and may reintroduce CocoaPods scaffolding.

The example is SPM-only (no `Podfile`). CloudPayments is resolved from the
plugin's `Package.swift` at build time. If you disable SPM in a consumer app,
add the CocoaPods fallback from the package README before building.

## Trying a payment

The screen is preloaded with the CloudPayments demo Public ID
(`test_api_00000000000000000000002`). Replace `_publicId` in `lib/main.dart`
with your own from <https://merchant.cloudpayments.ru/> to see payments in your
dashboard — a Public ID is not a secret and is safe to ship in an app.

Test card numbers live in the CloudPayments documentation and in your
dashboard's test settings; which ones trigger 3-D Secure depends on how your
account is configured, so check there rather than guessing.

## What the example shows

- `lib/card_form.dart` — validation, formatting and payment-system detection,
  all local, using `CardUtils` and the bundled input formatters.
- `lib/main.dart` — `CloudpaymentsSdk.pay()`, the one call that runs cryptogram,
  charge and 3-D Secure.
- `lib/result_view.dart` — an exhaustive `switch` over `PaymentResult`. Add a
  new outcome to the sealed hierarchy and this file stops compiling until it is
  handled, which is the point.
