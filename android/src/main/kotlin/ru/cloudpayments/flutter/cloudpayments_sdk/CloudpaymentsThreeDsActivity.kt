package ru.cloudpayments.flutter.cloudpayments_sdk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import androidx.appcompat.app.AppCompatActivity
import ru.cloudpayments.sdk.ui.dialogs.ThreeDsDialogFragment

/**
 * Hosts the official SDK's [ThreeDsDialogFragment].
 *
 * The fragment resolves its listener by casting its target fragment and then
 * its host — there is no setter — so it can only report back to a host that
 * implements [ThreeDsDialogFragment.ThreeDSDialogListener]. A plain
 * `FlutterActivity` does not, which is the entire reason this Activity exists.
 *
 * It answers through `setResult`, and the plugin turns that into the Dart
 * future's value.
 */
class CloudpaymentsThreeDsActivity :
    AppCompatActivity(),
    ThreeDsDialogFragment.ThreeDSDialogListener {

    companion object {
        const val EXTRA_ACS_URL = "ru.cloudpayments.flutter.acsUrl"
        const val EXTRA_PA_REQ = "ru.cloudpayments.flutter.paReq"
        const val EXTRA_MD = "ru.cloudpayments.flutter.md"
        const val EXTRA_PA_RES = "ru.cloudpayments.flutter.paRes"
        const val EXTRA_STATUS = "ru.cloudpayments.flutter.status"
        const val EXTRA_MESSAGE = "ru.cloudpayments.flutter.message"
        const val EXTRA_HTML = "ru.cloudpayments.flutter.html"

        const val STATUS_SUCCESS = "success"
        const val STATUS_FAILURE = "failure"
        const val STATUS_CANCELLED = "cancelled"

        private const val FRAGMENT_TAG = "cloudpayments_three_ds"

        /** Builds the intent that opens the screen. */
        fun newIntent(
            context: Context,
            acsUrl: String,
            paReq: String,
            md: String,
        ): Intent = Intent(context, CloudpaymentsThreeDsActivity::class.java)
            .putExtra(EXTRA_ACS_URL, acsUrl)
            .putExtra(EXTRA_PA_REQ, paReq)
            .putExtra(EXTRA_MD, md)
    }

    private var reported = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val acsUrl = intent.getStringExtra(EXTRA_ACS_URL).orEmpty()
        val paReq = intent.getStringExtra(EXTRA_PA_REQ).orEmpty()
        val md = intent.getStringExtra(EXTRA_MD).orEmpty()

        if (acsUrl.isEmpty() || paReq.isEmpty() || md.isEmpty()) {
            finishWith(STATUS_FAILURE, message = "Missing 3-D Secure parameters.")
            return
        }

        // The SDK's dialog is not cancelable and swallows the back press, but a
        // predictive-back gesture or a hardware back on some devices still
        // reaches us. Treat it as the user walking away.
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = finishWith(STATUS_CANCELLED)
            },
        )

        // Only on a fresh start: after a configuration change the fragment
        // manager restores the dialog itself, and showing a second one would
        // restart authentication.
        if (savedInstanceState == null &&
            supportFragmentManager.findFragmentByTag(FRAGMENT_TAG) == null
        ) {
            ThreeDsDialogFragment
                .newInstance(acsUrl, paReq, md)
                .show(supportFragmentManager, FRAGMENT_TAG)
        }
    }

    // --- ThreeDSDialogListener ------------------------------------------------

    override fun onAuthorizationCompleted(md: String, paRes: String) {
        finishWith(STATUS_SUCCESS, md = md, paRes = paRes)
    }

    override fun onAuthorizationFailed(error: String?) {
        // The SDK passes null only from its close button, and the raw ACS page
        // otherwise — so a null here means the user dismissed the screen.
        if (error == null) {
            finishWith(STATUS_CANCELLED)
        } else {
            finishWith(
                STATUS_FAILURE,
                message = "3-D Secure authentication failed.",
                html = error,
            )
        }
    }

    // --- plumbing -------------------------------------------------------------

    private fun finishWith(
        status: String,
        md: String? = null,
        paRes: String? = null,
        message: String? = null,
        html: String? = null,
    ) {
        if (reported) return
        reported = true

        val data = Intent().putExtra(EXTRA_STATUS, status)
        md?.let { data.putExtra(EXTRA_MD, it) }
        paRes?.let { data.putExtra(EXTRA_PA_RES, it) }
        message?.let { data.putExtra(EXTRA_MESSAGE, it) }
        html?.let { data.putExtra(EXTRA_HTML, it) }

        setResult(Activity.RESULT_OK, data)
        finish()
    }
}
