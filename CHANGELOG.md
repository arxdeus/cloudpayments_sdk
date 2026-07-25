# Changelog

## [0.3.0](https://github.com/arxdeus/cloudpayments_sdk/compare/v0.2.0..0.3.0) - 2026-07-25

### Bug Fixes

- **(android)** require AGP 8.13+ for compileSdk 37 - ([3fac1d8](https://github.com/arxdeus/cloudpayments_sdk/commit/3fac1d8ed7cfeab498c1e3b63c92f36ad0bcc23e))
- strict lint rules - ([c2aa900](https://github.com/arxdeus/cloudpayments_sdk/commit/c2aa9003b01039a290a4d2411dbcbe0cf022e75e))

### Documentation

- **(example)** correct the Android and iOS setup notes - ([68c9a5c](https://github.com/arxdeus/cloudpayments_sdk/commit/68c9a5c65d1fd912fdcfb7c610ec21afb72870f7))

### Features

- **(ios)** resolve CloudPayments via Swift PM - ([ceb9ce9](https://github.com/arxdeus/cloudpayments_sdk/commit/ceb9ce94f16a04b853fc01ec5092b9a598a8a874))
- annotate the public API with @immutable and @useResult - ([e92b60b](https://github.com/arxdeus/cloudpayments_sdk/commit/e92b60bcac09466fea4ae6b8f1cea1ed539b42a8))
- CI/CD workflow - ([b921cb5](https://github.com/arxdeus/cloudpayments_sdk/commit/b921cb5df4ad631fd3c8c9dfe5ba057aca9955d9))

### Miscellaneous Chores

- **(README)** add contact information for adopting the package - ([c736f19](https://github.com/arxdeus/cloudpayments_sdk/commit/c736f194f3b72873bc96d202ef5913d03ba005e2))
- **(example)** check in the iOS Runner project - ([587201f](https://github.com/arxdeus/cloudpayments_sdk/commit/587201fe16d8bf865e551a322eccbfebf9b4598d))
- **(example)** add the missing project files - ([2ca6b46](https://github.com/arxdeus/cloudpayments_sdk/commit/2ca6b4648f77ea5352e6d916547c1a20e9e448c6))
- **(skip)** change `dart` to `flutter` in CI/CD - ([fb7c15b](https://github.com/arxdeus/cloudpayments_sdk/commit/fb7c15b6f151ba922991b0887c6665229147dd63))
- `.pubignore` to exclude unnecessary files - ([120e7ea](https://github.com/arxdeus/cloudpayments_sdk/commit/120e7ea4fcbc0b6ef587a5ba4cb910acbccb5d73))
- remove .fvmrc - ([a4bd45f](https://github.com/arxdeus/cloudpayments_sdk/commit/a4bd45fa53ab9445a6076f09e66d67db941b7fa7))

### Refactoring

- move the plugin identifier to dev.arxdeus.flutter - ([d4d51ee](https://github.com/arxdeus/cloudpayments_sdk/commit/d4d51ee021d0ca748af45651801c6492ce7750c5))

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
