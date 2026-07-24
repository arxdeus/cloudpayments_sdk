import UIKit
import WebKit

/// Hosts the `WKWebView` that `ThreeDsProcessor` builds.
///
/// The CloudPayments SDK loads the issuer's Access Control Server page into a
/// web view and then hands that view to the app through
/// `ThreeDsDelegate.willPresentWebView` — it never presents anything itself.
/// This controller is the "somewhere to put it" that the SDK expects.
final class CloudpaymentsThreeDsViewController: UIViewController {
    /// Called when the user dismisses the screen without finishing.
    ///
    /// The plugin clears this once it is done with the screen, so a late
    /// teardown cannot answer for a newer 3-D Secure session.
    var onCancel: (() -> Void)?

    /// Called once the screen is actually on screen. The plugin uses it to
    /// stand down the watchdog that guards against a presentation that never
    /// happens.
    var onDidAppear: (() -> Void)?

    private let webView: WKWebView
    private var reportedCancel = false

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // The issuer's page can open alerts and pop-ups; without a UI delegate
        // WebKit swallows them and the cardholder is stuck on a dead page.
        webView.uiDelegate = self

        let closeButton = UIButton(type: .system)
        // A glyph rather than a word: the cardholder's language is the
        // issuer's, not the app's, so any label here would be wrong as often
        // as it was right.
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = UIButton(type: .close).accessibilityLabel
            ?? "Close"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(closeButton)
        view.addSubview(webView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            webView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onDidAppear?()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // A swipe-down dismissal never goes through the button, so catch it
        // here too. Harmless after a completed payment: the plugin detaches
        // onCancel before it tears the screen down.
        reportCancel()
    }

    @objc private func closeTapped() {
        reportCancel()
    }

    private func reportCancel() {
        guard !reportedCancel else { return }
        reportedCancel = true

        // Close ourselves rather than depending on the plugin to do it. If the
        // plugin has already moved on, this is the only thing standing between
        // the cardholder and a full-screen page they cannot leave.
        if presentingViewController != nil, !isBeingDismissed {
            dismiss(animated: true)
        }

        onCancel?()
    }
}

// MARK: - WKUIDelegate

extension CloudpaymentsThreeDsViewController: WKUIDelegate {
    /// Pop-ups (`target="_blank"`, `window.open`) load in place — a second web
    /// view would escape the flow the SDK is watching.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame?.isMainFrame != true {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        presentOrComplete(alert) { completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        presentOrComplete(alert) { completionHandler(false) }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(nil)
        })
        presentOrComplete(alert) { completionHandler(nil) }
    }

    /// WebKit deadlocks the page if a JavaScript panel's completion handler is
    /// never called, so a presentation that cannot happen must still answer.
    private func presentOrComplete(
        _ alert: UIAlertController,
        fallback: @escaping () -> Void
    ) {
        guard presentedViewController == nil, !isBeingDismissed else {
            fallback()
            return
        }
        present(alert, animated: true)
    }
}
