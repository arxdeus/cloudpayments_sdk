# Changelog

## 0.3.0

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
