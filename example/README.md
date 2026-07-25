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

- `minSdk = 24` and Java/Kotlin target 17
- `manifestPlaceholders = [cpSdkHost: ""]` — without it the manifest merger
  fails, because the SDK's own manifest declares a deep-link host through that
  placeholder

`android/build.gradle` also adds the JitPack repository, which is the only place
the CloudPayments Android SDK is published.

### iOS

The Xcode project is not checked in — generate it once:

```bash
cd example
flutter create --platforms=ios .
```

That regenerates `ios/Runner.xcodeproj` **and overwrites `ios/Podfile`**, so
restore the Podfile from git afterwards (`git checkout ios/Podfile`) — it pins
CocoaPods' `platform` and `post_install` deployment target to iOS 15.0.

Also set the **Xcode project's** Minimum Deployments to **15.0** (Flutter's
template still defaults to 13.0). Without that, SPM fails because CloudPayments
requires iOS 15:

- In `ios/Runner.xcodeproj/project.pbxproj`, set every
  `IPHONEOS_DEPLOYMENT_TARGET` to `15.0`, or
- In Xcode: Runner target → General → Minimum Deployments → iOS 15.0

With Swift Package Manager enabled (default on Flutter 3.44+), CloudPayments is
resolved from the plugin's `Package.swift` at build time — no git pods and no
separate `pod install` step for that SDK. If you disable SPM, add the CocoaPods
fallback from the package README before building.

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
