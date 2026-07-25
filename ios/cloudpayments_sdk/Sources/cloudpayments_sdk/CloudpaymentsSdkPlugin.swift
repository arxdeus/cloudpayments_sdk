import Cloudpayments
import Flutter
import UIKit
import WebKit

/// Bridges Dart to the official CloudPayments iOS SDK.
///
/// Only two things happen here, because only two things need native code:
/// building a card cryptogram with `Card`, and driving `ThreeDsProcessor`'s
/// 3-D Secure WebView. Validation, HTTP and orchestration all live in Dart.
public class CloudpaymentsSdkPlugin: NSObject, FlutterPlugin {
    private static let channelName = "dev.arxdeus.flutter/cloudpayments_sdk"

    /// The CloudPayments iOS SDK release this plugin is written against.
    /// Reported to Dart for diagnostics; keep it in step with Package.swift.
    private static let nativeSdkVersion = "2.1.6"

    /// How long to wait for the 3-D Secure screen to actually appear.
    ///
    /// `ThreeDsProcessor` silently does nothing when its own request to the
    /// Access Control Server fails outright, and `present` can quietly refuse
    /// if the presenter is busy — either way the Dart future would hang. The
    /// watchdog stands down once the screen reports that it is on screen, so
    /// it never cuts a cardholder off mid-authentication.
    private static let acsTimeout: TimeInterval = 90

    private let threeDsProcessor = ThreeDsProcessor()

    private var pendingThreeDsResult: FlutterResult?
    private var threeDsController: CloudpaymentsThreeDsViewController?
    private var acsWatchdog: Timer?

    /// The Dart call waiting on the ready-made payment form, if any.
    ///
    /// Held strongly along with the configuration: `PaymentConfiguration`
    /// keeps its delegate weakly, so nothing else would keep the callbacks
    /// alive for the life of the form.
    private var pendingFormResult: FlutterResult?
    private var formConfiguration: PaymentConfiguration?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = CloudpaymentsSdkPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "createCryptogram":
            createCryptogram(call, result)
        case "show3ds":
            showThreeDs(call, result)
        case "presentPaymentForm":
            presentPaymentForm(call, result)
        case "nativeSdkVersion":
            result(Self.nativeSdkVersion)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Cryptogram

    private func createCryptogram(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let cardNumber = arguments["cardNumber"] as? String,
              let expiryDate = arguments["expiryDate"] as? String,
              let cvv = arguments["cvv"] as? String,
              let publicId = arguments["publicId"] as? String,
              let publicKey = arguments["publicKey"] as? String,
              let keyVersion = arguments["keyVersion"] as? Int,
              !cardNumber.isEmpty, !expiryDate.isEmpty, !cvv.isEmpty,
              !publicId.isEmpty, !publicKey.isEmpty
        else {
            result(FlutterError(
                code: "invalid_arguments",
                message: "createCryptogram needs cardNumber, expiryDate, cvv, "
                    + "publicId, publicKey and keyVersion.",
                details: nil
            ))
            return
        }

        let cryptogram = Card.makeCardCryptogramPacket(
            cardNumber: cardNumber,
            expDate: expiryDate,
            cvv: cvv,
            merchantPublicID: publicId,
            publicKey: publicKey,
            keyVersion: keyVersion
        )

        guard let cryptogram = cryptogram, !cryptogram.isEmpty else {
            // The SDK returns nil without saying why. The input has already
            // been validated in Dart, so the likely causes are a card number
            // the SDK's own Luhn check rejects or a stale public key.
            result(FlutterError(
                code: "cryptogram_failed",
                message: "The CloudPayments SDK could not encrypt the card. Check "
                    + "that the card details are valid and the public key is current.",
                details: nil
            ))
            return
        }

        result(cryptogram)
    }

    // MARK: - 3-D Secure

    private func showThreeDs(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let acsUrl = arguments["acsUrl"] as? String,
              let paReq = arguments["paReq"] as? String,
              let md = arguments["md"] as? String,
              !acsUrl.isEmpty, !paReq.isEmpty, !md.isEmpty
        else {
            result(FlutterError(
                code: "invalid_arguments",
                message: "show3ds needs acsUrl, paReq and md.",
                details: nil
            ))
            return
        }

        guard URL(string: acsUrl) != nil else {
            // ThreeDsProcessor drops the request on the floor when the URL will
            // not parse, so catch it here rather than hanging.
            result(FlutterError(
                code: "invalid_arguments",
                message: "The issuer's AcsUrl is not a valid URL: \(acsUrl)",
                details: nil
            ))
            return
        }

        guard pendingThreeDsResult == nil else {
            result(FlutterError(
                code: "already_running",
                message: "A 3-D Secure screen is already open.",
                details: nil
            ))
            return
        }

        guard Self.topViewController() != nil else {
            result(FlutterError(
                code: "no_view_controller",
                message: "3-D Secure needs a visible view controller to present from.",
                details: nil
            ))
            return
        }

        pendingThreeDsResult = result
        startAcsWatchdog()

        threeDsProcessor.make3DSPayment(
            with: ThreeDsData(transactionId: md, paReq: paReq, acsUrl: acsUrl),
            delegate: self
        )
    }

    private func startAcsWatchdog() {
        cancelAcsWatchdog()
        acsWatchdog = Timer.scheduledTimer(
            withTimeInterval: Self.acsTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.finishThreeDs([
                "status": "failure",
                "message": "The 3-D Secure screen did not open in time.",
            ])
        }
    }

    private func cancelAcsWatchdog() {
        acsWatchdog?.invalidate()
        acsWatchdog = nil
    }

    private func presentThreeDs(_ webView: WKWebView, retriesLeft: Int = 20) {
        // A queued retry must not resurrect a call that has already been
        // settled by the watchdog or by a cancellation.
        guard pendingThreeDsResult != nil else { return }

        guard let presenter = Self.topViewController() else {
            finishThreeDs([
                "status": "failure",
                "message": "3-D Secure needs a visible view controller to present from.",
            ])
            return
        }

        // UIKit silently refuses to present from a controller that is
        // mid-transition or already presenting — no throw, no completion, just
        // nothing on screen. Wait for it to settle instead of losing the
        // screen; the previous screen's own dismissal animation is the common
        // case here.
        if presenter.isBeingPresented
            || presenter.isBeingDismissed
            || presenter.presentedViewController != nil {
            guard retriesLeft > 0 else {
                finishThreeDs([
                    "status": "failure",
                    "message": "3-D Secure could not be shown: the screen in front of "
                        + "it never settled.",
                ])
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.presentThreeDs(webView, retriesLeft: retriesLeft - 1)
            }
            return
        }

        let controller = CloudpaymentsThreeDsViewController(webView: webView)
        controller.onCancel = { [weak self] in
            self?.finishThreeDs(["status": "cancelled"])
        }
        controller.onDidAppear = { [weak self] in
            // The screen is up; nothing left for the watchdog to guard.
            self?.cancelAcsWatchdog()
        }
        controller.modalPresentationStyle = .fullScreen
        threeDsController = controller
        presenter.present(controller, animated: true)
    }

    /// Delivers the outcome to Dart and tears the screen down.
    ///
    /// Safe to call more than once — only the first call is reported, which is
    /// what makes the swipe-to-dismiss path harmless after a success.
    ///
    /// Two ordering decisions matter here:
    ///
    /// * The screen is dismissed *unconditionally*, before the result guard.
    ///   A controller can outlive its Dart call — the watchdog fires, then the
    ///   Access Control Server finally answers — and leaving it up would strand
    ///   the user behind a full-screen web view whose close button does
    ///   nothing.
    /// * The result is delivered without waiting for the dismissal. UIKit skips
    ///   a `dismiss` completion when the presentation transition is still
    ///   running, and a fast frictionless challenge can complete inside that
    ///   window; a Dart future that never completes is far worse than a screen
    ///   that is still animating away.
    private func finishThreeDs(_ payload: [String: Any]) {
        cancelAcsWatchdog()
        dismissThreeDs()

        guard let result = pendingThreeDsResult else { return }
        pendingThreeDsResult = nil
        result(payload)
    }

    /// Takes the 3-D Secure screen down, retrying while UIKit is busy.
    ///
    /// The reference is held until the dismissal actually completes: releasing
    /// it early — while the presentation transition is still running, when
    /// UIKit ignores `dismiss` outright — would leave a full-screen web view on
    /// top of the app with nothing left that could close it.
    private func dismissThreeDs(retriesLeft: Int = 30) {
        guard let controller = threeDsController else { return }

        // Detach the callbacks first: once the plugin is done with a screen,
        // that screen's teardown must not be able to answer for a later one.
        controller.onCancel = nil
        controller.onDidAppear = nil

        if controller.isBeingPresented || controller.isBeingDismissed {
            guard retriesLeft > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.dismissThreeDs(retriesLeft: retriesLeft - 1)
            }
            return
        }

        controller.dismiss(animated: true) { [weak self] in
            if self?.threeDsController === controller {
                self?.threeDsController = nil
            }
        }
    }

    // MARK: - The ready-made payment form

    private func presentPaymentForm(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        guard let arguments = call.arguments as? [String: Any],
              let publicId = arguments["publicId"] as? String,
              let amount = arguments["amount"] as? String,
              !publicId.isEmpty, !amount.isEmpty
        else {
            result(FlutterError(
                code: "invalid_arguments",
                message: "presentPaymentForm needs publicId and amount.",
                details: nil
            ))
            return
        }

        guard pendingFormResult == nil else {
            result(FlutterError(
                code: "already_running",
                message: "The payment form is already open.",
                details: nil
            ))
            return
        }

        guard let presenter = Self.topViewController() else {
            result(FlutterError(
                code: "no_view_controller",
                message: "The payment form needs a visible view controller to "
                    + "present from.",
                details: nil
            ))
            return
        }

        let paymentData = Self.buildPaymentData(from: arguments, amount: amount)

        let methodOrder = (arguments["methodOrder"] as? [String] ?? [])
            .compactMap { PaymentMethodType(rawValue: $0) }

        let configuration = PaymentConfiguration(
            publicId: publicId,
            paymentData: paymentData,
            delegate: self,
            uiDelegate: nil,
            emailBehavior: Self.emailBehavior(arguments["emailBehavior"] as? String),
            paymentMethodSequence: methodOrder,
            singlePaymentMode: (arguments["singleMethod"] as? String)
                .flatMap { PaymentMethodType(rawValue: $0) },
            useDualMessagePayment: arguments["twoStage"] as? Bool ?? false,
            disableApplePay: arguments["disableApplePay"] as? Bool ?? true,
            showResultScreenForSinglePaymentMode:
                arguments["showResultScreen"] as? Bool ?? true,
            successRedirectUrl: arguments["successRedirectUrl"] as? String,
            failRedirectUrl: arguments["failRedirectUrl"] as? String
        )

        pendingFormResult = result
        formConfiguration = configuration

        PaymentOptionsViewController.present(with: configuration, from: presenter)
    }

    private static func buildPaymentData(
        from arguments: [String: Any],
        amount: String
    ) -> PaymentData {
        var data = PaymentData()
            .setAmount(amount)
            .setCurrency(arguments["currency"] as? String ?? "RUB")

        if let description = arguments["description"] as? String {
            data = data.setDescription(description)
        }
        if let accountId = arguments["accountId"] as? String {
            data = data.setAccountId(accountId)
        }
        if let invoiceId = arguments["invoiceId"] as? String {
            data = data.setInvoiceId(invoiceId)
        }
        if let email = arguments["email"] as? String {
            data = data.setEmail(email)
        }
        if let payer = arguments["payer"] as? [String: Any] {
            data = data.setPayer(PaymentDataPayer(
                firstName: payer["FirstName"] as? String ?? "",
                lastName: payer["LastName"] as? String ?? "",
                middleName: payer["MiddleName"] as? String ?? "",
                birth: payer["Birth"] as? String ?? "",
                address: payer["Address"] as? String ?? "",
                street: payer["Street"] as? String ?? "",
                city: payer["City"] as? String ?? "",
                country: payer["Country"] as? String ?? "",
                phone: payer["Phone"] as? String ?? "",
                postcode: payer["Postcode"] as? String ?? ""
            ))
        }
        if let receipt = arguments["receipt"] as? [String: Any] {
            data = data.setReceipt(receipt)
        }
        if let recurrent = arguments["recurrent"] as? [String: Any],
           let interval = recurrent["interval"] as? String,
           let period = recurrent["period"] as? Int {
            data = data.setRecurrent(Recurrent(
                interval: interval,
                period: period,
                receipt: recurrent["receipt"] as? [String: Any],
                amount: (recurrent["amount"] as? NSNumber).map {
                    Decimal(string: $0.stringValue) ?? Decimal($0.doubleValue)
                },
                startDate: recurrent["startDate"] as? String,
                maxPeriods: recurrent["maxPeriods"] as? Int
            ))
        }
        if let jsonData = arguments["jsonData"] as? String {
            data = data.setJsonData(jsonData)
        }

        return data
    }

    private static func emailBehavior(_ raw: String?) -> EmailBehaviorType {
        switch raw {
        case "REQUIRED": return .required
        case "HIDDEN": return .hidden
        default: return .optional
        }
    }

    /// Delivers the form's outcome to Dart. Safe to call more than once.
    private func finishForm(_ payload: [String: Any]) {
        guard let result = pendingFormResult else { return }
        pendingFormResult = nil
        formConfiguration = nil
        result(payload)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first

        guard let root = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? scene?.windows.first?.rootViewController
        else {
            return nil
        }

        // Walk all the way to the deepest presented controller. Stopping
        // early would return a controller that already has a
        // presentedViewController, and UIKit refuses to present from one of
        // those just as firmly as from a controller mid-transition.
        // presentThreeDs waits out any transition it finds here.
        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - ThreeDsDelegate

extension CloudpaymentsSdkPlugin: ThreeDsDelegate {
    /// The SDK builds the `WKWebView` but leaves presenting it to the host —
    /// so this is where the 3-D Secure screen actually appears.
    public func willPresentWebView(_ webView: WKWebView) {
        // The Access Control Server can answer after the watchdog has already
        // given up. Putting a screen on top of the app at that point would
        // trap the user, so drop it instead.
        guard pendingThreeDsResult != nil else { return }
        presentThreeDs(webView)
    }

    public func onAuthorizationCompleted(with md: String, paRes: String) {
        finishThreeDs([
            "status": "success",
            "md": md,
            "paRes": paRes,
        ])
    }

    public func onAuthorizationFailed(with html: String) {
        finishThreeDs([
            "status": "failure",
            "message": "3-D Secure authentication failed.",
            "html": html,
        ])
    }
}

// MARK: - PaymentDelegate

extension CloudpaymentsSdkPlugin: PaymentDelegate {
    public func onPaymentFinished(_ transactionId: Int64?) {
        var payload: [String: Any] = ["status": "succeeded"]
        if let transactionId = transactionId {
            payload["transactionId"] = transactionId
        }
        finishForm(payload)
    }

    public func onPaymentFailed(_ errorMessage: String?) {
        var payload: [String: Any] = ["status": "failed"]
        if let errorMessage = errorMessage {
            payload["message"] = errorMessage
        }
        finishForm(payload)
    }

    public func onPaymentClosed() {
        // The SDK reports this when the form is dismissed, including after a
        // finished payment — finishForm ignores everything after the first
        // answer, so a close that follows a success stays harmless.
        finishForm(["status": "closed"])
    }
}
