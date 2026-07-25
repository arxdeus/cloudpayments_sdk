# cloudpayments_sdk

CloudPayments for Flutter, built on the **official CloudPayments native SDKs**.

Two ways to take a payment. Pick the first unless you have a reason not to.

## 1. CloudPayments' own form

```dart
final cp = CloudpaymentsSdk(publicId: 'pk_xxxxxxxxxxxxxxxxxxxxxxxxx');

final result = await cp.presentPaymentForm(
  details: const PaymentDetails(amount: 499, invoiceId: 'ORDER-42'),
);

switch (result) {
  case FormPaymentSucceeded(:final transactionId): print('Paid #$transactionId');
  case FormPaymentFailed(:final reasonCode):       print('Declined, $reasonCode');
  case FormPaymentClosed():                        print('User closed the form');
}
```

That is the entire integration. The native SDK draws the UI, validates the
card, runs 3-D Secure, and offers whichever of СБП, T‑Pay, SberPay, Долями and
foreign cards your terminal has enabled. You build no screens.

### Subscriptions

Add `recurrent` and CloudPayments charges every following period **itself**,
server-side. Your app is never involved again, and no API secret is needed:

```dart
await cp.presentPaymentForm(
  details: const PaymentDetails(
    amount: 499,
    accountId: 'user-42',            // required — the subscription binds to it
    email: 'user@example.com',
  ),
  recurrent: const CloudpaymentsRecurrent(
    interval: RecurrentInterval.month,
    period: 1,
  ),
);
```

## 2. Your own form

When you need to own the checkout UI:

```dart
final result = await cp.pay(
  card: CardData(number: '4111 1111 1111 1111', expiryDate: '12/30', cvv: '123'),
  details: const PaymentDetails(amount: 100, invoiceId: 'ORDER-42'),
);

switch (result) {
  case PaymentSuccess(:final transaction):  print('Paid #${transaction.transactionId}');
  case PaymentDeclined(:final cardHolderMessage): print(cardHolderMessage);
  case PaymentCancelled():                  print('User closed 3-D Secure');
  case PaymentFailure(:final message):      print(message);
  case PaymentRequiresThreeDs():            break; // pay() resolves this itself
}
```

That call encrypts the card in the native SDK, sends `payments/cards/charge`,
opens the native 3-D Secure screen if the issuer asks for one, posts the result
back, and reports the outcome. `CardUtils` and the bundled input formatters
give you validation, formatting and payment-system detection for the fields.

This path is card-only: no СБП, no T‑Pay, no wallets. Those live in the form.

---

## What runs where

| Step | Where it runs |
| --- | --- |
| **The ready-made form**, and everything inside it | **Native**: `PaymentActivity` (Android), `PaymentOptionsViewController` (iOS) |
| Card number / expiry / CVV validation, payment-system detection, formatting | Dart, locally |
| RSA public key fetch (`payments/publickey`) | Dart |
| **Card cryptogram** | **Native**: `Card.createHexPacketFromData` (Android), `Card.makeCardCryptogramPacket` (iOS) |
| `charge` / `auth` / `ThreeDSCallback` | Dart, over HTTPS |
| **3-D Secure screen** (own-form path) | **Native**: an `Activity` hosting the SDK's `ThreeDsDialogFragment` (Android), a presented `UIViewController` hosting `ThreeDsProcessor`'s `WKWebView` (iOS) |

Doing the HTTP in Dart rather than through the native API clients is deliberate:
the 2.x native SDKs removed `charge`/`auth`/`post3ds` from their public API
entirely, and their READMEs now tell you to call the REST API yourself.

---

## Install

```yaml
dependencies:
  cloudpayments_sdk: ^0.3.0
```

Android still needs a one-line JitPack repository edit. On iOS, Swift Package
Manager (default on Flutter 3.44+) resolves CloudPayments from the plugin's
`Package.swift` — no Podfile git pods. If you disable SPM, use the CocoaPods
fallback below.

### Android

The SDK is published on JitPack. In `android/build.gradle`:

```gradle
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://jitpack.io") }   // add this
    }
}
```

In `android/app/build.gradle`:

```gradle
android {
    // Required, not a preference: the CloudPayments AAR declares
    // minCompileSdk=37 and AGP fails the build of anything lower. API 37 is
    // published only as `platforms;android-37.0`, so the minor level has to be
    // spelled out or AGP looks for a `platforms;android-37` that cannot exist.
    compileSdk {
        version = release(37) {
            it.minorApiLevel = 0
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17   // the SDK targets Java 17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    defaultConfig {
        minSdk = 24                                    // the SDK requires API 24

        // REQUIRED. The SDK's manifest declares a deep-link host through this
        // placeholder and the manifest merger fails without it. An empty string
        // is what CloudPayments documents for card-only flows. Add to the map
        // instead of assigning it — the Flutter Gradle plugin has already put
        // `applicationName` in there, and replacing the map drops it.
        manifestPlaceholders["cpSdkHost"] = ""
    }
}
```

Your app also needs Kotlin **2.4.0 or newer** — the CloudPayments SDK is compiled
with it, and an older compiler cannot read its metadata. Set it in
`android/settings.gradle`:

```gradle
plugins {
    id "org.jetbrains.kotlin.android" version "2.4.0" apply false
}
```

Your app also needs **Android Gradle Plugin 8.13.0 or newer**. That is the first
release that understands minor-versioned SDK platforms; earlier versions cannot
resolve `compileSdk` 37 at all and fail with
`Failed to find Platform SDK with path: platforms;android-37`. The example app
is built with AGP 9.0.1 and Gradle 9.1.0.

These requirements come from the SDK, not from this package. Resolved
dependency versions, `minCompileSdk` and the manifest placeholder were all read
out of the published AAR
(`ru.cloudpayments.gitpub.integrations.sdk:cloudpayments-android:2.1.5`).

To pin a different SDK release, set `ext.cloudpaymentsAndroidSdkVersion` in
`android/build.gradle` before the plugin projects are evaluated.

### iOS

Minimum deployment target is **iOS 15.0**. Set that on the Xcode **Runner**
target as well (Flutter's `flutter create` template still defaults to 13.0) —
otherwise SPM cannot link CloudPayments.

With Swift Package Manager enabled (the default on Flutter 3.44+), you do not
need to edit `ios/Podfile`. The plugin declares CloudPayments **2.1.6** from
<https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-ios.git> in its
`Package.swift`, and Flutter resolves it at build time.

#### CocoaPods fallback

If SPM is off (`flutter config --no-enable-swift-package-manager`, or
`enable-swift-package-manager: false` in your app `pubspec.yaml`), add both
CloudPayments pods to `ios/Podfile` — the plugin's podspec depends on them but
cannot say where they live:

```ruby
platform :ios, '15.0'

target 'Runner' do
  use_frameworks!

  cp_git = 'https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-ios.git'
  pod 'Cloudpayments',           :git => cp_git, :tag => '2.1.6'
  pod 'CloudpaymentsNetworking', :git => cp_git, :tag => '2.1.6'

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end
```

> The podspec inside that repository still names `github.com/cloudpayments` as
> its source, and that repository is archived at 1.3.3. The `:git` override
> above is what makes 2.x resolve under CocoaPods.

---

## Where the code lives

CloudPayments archived every repository on GitHub in August 2023. The maintained
SDKs are on their own GitLab:

- Android — <https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-android> (2.1.5)
- iOS — <https://gitpub.cloudpayments.ru/integrations/sdk/cloudpayments-ios> (2.1.6)

This package is written against those versions. The GitHub mirrors
(`CloudPayments-SDK-Android`, `CloudPayments-SDK-iOS`, both 1.3.3) have a
different API surface and will not compile against this plugin.

---

## Security

**Your Public ID is not a secret.** It identifies your account, it is meant to
ship in client applications, and both official SDKs put it in the request body.

**Your API secret is.** Anyone who extracts it from an app binary can refund,
void and charge on your account. This package therefore splits the API in two:

| Public ID only — safe in an app | API secret required — backend only |
| --- | --- |
| `charge`, `auth` | `confirm`, `voidPayment`, `refund` |
| `completeThreeDs` | `post3ds`, `getTransaction`, `testConnection` |
| `getPublicKey`, `getBinInfo` | `chargeToken`, `authToken` |

Calling anything in the right-hand column without a secret throws
`CloudpaymentsConfigurationException` with an explanation, rather than failing
somewhere in the network stack. `CloudpaymentsApiClient` accepts an `apiSecret`
so you can reuse the same models and client in server-side Dart — just never in
the app.

**Card data.** `CardData` exists for the few milliseconds between the form and
`createCryptogram`. It does not implement `==`, and its `toString()` returns the
masked number, so it cannot leak into a log or a crash report by accident. Never
persist it, never send it anywhere but through the cryptogram.

---

## Going step by step

`pay()` is three calls stitched together. Each is available on its own:

```dart
final cryptogram = await cp.createCryptogram(card);

final result = await cp.api.charge(
  const PaymentDetails(amount: 100).asCardPayment(cryptogram: cryptogram),
);

if (result case PaymentRequiresThreeDs()) {
  final finished = await cp.resolveThreeDs(result);   // opens the native screen
}
```

`cp.api` is a full `CloudpaymentsApiClient` if you want the rest of the API.

### Two-stage payments

```dart
await cp.pay(card: card, details: details, twoStage: true);
// or
await cp.presentPaymentForm(
  details: details,
  options: const PaymentFormOptions(twoStage: true),
);
```

The funds are held and the transaction comes back `Authorized`. Capture with
`confirm` or release with `void` — both need the API secret, so both belong on
your backend.

### Testing a subscription

You cannot watch a monthly charge in an afternoon, so shorten the cycle instead
of waiting:

```dart
recurrent: const CloudpaymentsRecurrent(
  interval: RecurrentInterval.day,   // not month
  period: 1,
  maxPeriods: 3,
),
```

Then: check the subscription appears in the dashboard under Подписки, and
subscribe to the `recurrent` webhook — the automatic charges are server-side
events, so your app never sees them. To prove the charging mechanism itself
right now, take a payment with `saveCard: true` and charge the returned token
from your backend with `api.chargeToken(...)`; that is exactly what the
subscription engine does on schedule.

What needs the API secret, and therefore your backend: charging off-schedule,
and changing or cancelling a subscription. Creating one does not.

### Apple Pay and Google Pay

Wallet tokens go in place of a cryptogram, with a specific cardholder name:

```dart
await cp.payWithCryptogram(
  cryptogram: walletToken,
  details: details,
  cardHolderName: CardPaymentRequest.googlePayCardHolderName,
);
```

Obtaining the token itself is the wallet SDK's job; this package does not wrap
it.

### Fiscal receipts (54-ФЗ)

```dart
PaymentDetails(
  amount: 600,
  email: 'buyer@example.com',
  receipt: Receipt(
    taxationSystem: TaxationSystem.simplifiedIncome,
    email: 'buyer@example.com',
    items: [ReceiptItem(label: 'Coffee', price: 150, quantity: 2, vat: VatRate.vat20)],
  ),
)
```

The receipt is folded into `JsonData` under `CloudPayments.CustomerReceipt`,
merging with anything already there.

### Building your own card form

```dart
TextFormField(
  inputFormatters: const [CardNumberInputFormatter()],
  validator: (v) => CardUtils.isValidNumber(v ?? '') ? null : 'Check the number',
)
```

`CardUtils` also gives you `detectSystem`, `isValidExpiryDate`, `isValidCvv`,
`formatNumber`, `maskNumber` and `passesLuhn`. `ExpiryDateInputFormatter` and
`CvvInputFormatter` round out the form.

---

## What a result actually tells you

Business outcomes are values, not exceptions — a declined card is not an error.
Exceptions are reserved for real errors: `CloudpaymentsNetworkException`,
`CloudpaymentsApiException`, `CloudpaymentsCryptogramException`,
`CloudpaymentsConfigurationException`. All four are `sealed`, so a `switch` over
them is checked for exhaustiveness.

One thing to be aware of: **after a 3-D Secure payment made with a Public ID
alone, CloudPayments returns only success or failure, not the transaction.**
`PaymentSuccess.transaction` then carries the transaction id and little else —
`transaction.status` will be `TransactionStatus.unknown`. Confirm the final
state from your backend or from the `pay` webhook. (With an API secret the
plugin uses `payments/cards/post3ds` instead and the full transaction comes
back.)

If a 3-D Secure callback ever returns something unreadable, this package throws
rather than guessing — the payment may have gone through, so retrying blindly
could double-charge. Reconcile by `InvoiceId`. The Android SDK guesses "success"
in that situation; this package deliberately does not.

---

## Known limitations

- **3-D Secure 1 only** on the own-form path. Neither official SDK implements
  3-D Secure 2 there — no `creq`/`cres` handling exists in either codebase.
  CloudPayments absorbs version 2 behind its own ACS, so the version 1 flow is
  what mobile clients use. The ready-made form runs whatever the SDK's own
  pipeline supports.
- **Apple Pay and Google Pay are off.** The form can show Apple Pay, but it
  needs a merchant identifier and entitlements this package does not configure,
  so `PaymentFormOptions.disableApplePay` defaults to `true`. For a wallet
  token you already hold, `payWithCryptogram` sends it as the cryptogram.
- **Subscriptions can be created but not managed.** `/subscriptions/create`,
  `get`, `find`, `update` and `cancel` are not wrapped; they need the API
  secret and belong on your backend. Creating a subscription with a payment —
  which is what an app actually needs — is supported on both paths.
- **Card scanning is not wrapped.** Both SDKs accept a scanner implementation;
  this package passes none.
- **Android and iOS only.** There is no web or desktop implementation; the whole
  point is the native SDKs.
- **The native SDKs are large.** The Android AAR ships the full CloudPayments
  payment form, and pulls in Compose, Dagger, RxJava, Retrofit and Play Services
  Wallet. That cost is unavoidable while using the official SDK — its low-level
  `Card` and `ThreeDsDialogFragment` are not published separately.
- `IpAddress` is documented as required for cryptogram payments, and a mobile
  client cannot discover its own public address. Get it from your backend and
  pass it in `PaymentDetails.ipAddress`.

## Contributing

Bug reports and pull requests are welcome. This is an unofficial package; it is
not published or supported by CloudPayments.
