# Changelog

## Unreleased

- **The plugin identifier moved from `ru.cloudpayments.flutter` to
  `dev.arxdeus.flutter`.** This covers the method channel name, the Android
  package, namespace and Maven group, the 3-D Secure `Intent` extra keys and the
  ProGuard rules. Nothing in the Dart API changes, and the CloudPayments SDK
  dependencies (`ru.cloudpayments.sdk`, `ru.cloudpayments.gitpub…`) are
  untouched. Apps that keep their own ProGuard rules for the plugin classes have
  to update the package name there.

## 0.3.0

- Models, results, options and exceptions are annotated `@immutable`, and pure
  serialisers, parsers and validators are annotated `@useResult`, so the
  analyzer catches a mutable subclass or a discarded `toJson()` at compile time.
  `ReceiptItem` gained a `const` constructor as part of this; its `amount` is now
  computed on read rather than at construction, with the same value as before.
- **Android now requires AGP 8.13.0 or newer.** API 37 is published only as
  `platforms;android-37.0`, so older plugins cannot resolve the `compileSdk` 37
  the CloudPayments AAR demands and fail with
  `Failed to find Platform SDK with path: platforms;android-37`. The module
  declares its compile SDK through the `release(37) { minorApiLevel = 0 }` DSL.
- Fixed the `cpSdkHost` manifest placeholder replacing the whole placeholder map
  instead of adding to it, which dropped the `applicationName` placeholder the
  Flutter Gradle plugin sets and broke the manifest merge.

- **iOS dependency via Swift Package Manager.** The plugin's `Package.swift`
  pulls CloudPayments **2.1.6** from gitpub, so SPM-enabled apps (default on
  Flutter 3.44+) no longer add CloudPayments git pods to `ios/Podfile`. CocoaPods
  dual support remains: when SPM is disabled, the existing Podfile git-pod
  instructions still apply. Android still requires the JitPack repository.

## 0.2.0

- **The ready-made CloudPayments payment form.** `CloudpaymentsSdk.presentPaymentForm()`
  opens the native SDK's own checkout — `PaymentActivity` on Android,
  `PaymentOptionsViewController` on iOS — which handles card entry, 3-D Secure and
  whichever of СБП, T‑Pay, SberPay, Долями and foreign cards the terminal has enabled.
  Outcomes come back as a sealed `PaymentFormResult`.
- **Subscriptions.** `CloudpaymentsRecurrent` creates a subscription together with the
  first payment; CloudPayments charges every following period server-side, with no API
  secret and no further involvement from the app. Supported on both the form
  (`presentPaymentForm(recurrent: ...)`) and the low-level path
  (`PaymentDetails.recurrent`, folded into `JsonData`).
- `PaymentFormOptions` covers two-stage payments, the email field, payment-method order
  and single-method mode.

## 0.1.0

Initial release.

- Card data validation (Luhn, expiry, CVV, card system detection) implemented in pure Dart,
  using the same 14–19 digit range CloudPayments itself accepts.
- Card cryptogram packet generation delegated to the official CloudPayments native SDKs
  (`ru.cloudpayments.gitpub.integrations.sdk:cloudpayments-android` on Android,
  the `Cloudpayments` pod on iOS), with the RSA key fetched from `payments/publickey`
  and passed in explicitly so the first payment after a cold install cannot fail.
- CloudPayments Payment API client: `charge`, `auth`, `ThreeDSCallback`, `bins/info` and
  `payments/publickey` with a Public ID alone, plus `post3ds`, `confirm`, `void`, `refund`,
  `payments/get`, token payments and `test` for server-side use with an API secret.
- 3-D Secure handled by a native WebView screen: an `Activity` on Android and a presented
  `UIViewController` on iOS. Both official SDKs implement 3-D Secure 1 only.
- `CloudpaymentsSdk.pay()` runs the whole cycle in one call: cryptogram → charge or auth →
  3-D Secure → callback → outcome.
- Outcomes are values, not exceptions: `PaymentSuccess`, `PaymentDeclined`,
  `PaymentCancelled`, `PaymentFailure` and `PaymentRequiresThreeDs` form a sealed hierarchy.
  An outcome that genuinely cannot be determined raises rather than being guessed at.
