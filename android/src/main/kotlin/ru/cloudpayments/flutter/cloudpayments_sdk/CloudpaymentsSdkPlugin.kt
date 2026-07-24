package ru.cloudpayments.flutter.cloudpayments_sdk

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import ru.cloudpayments.sdk.api.models.PaymentDataPayer
import ru.cloudpayments.sdk.api.models.intent.CPRecurrent
import ru.cloudpayments.sdk.card.Card
import ru.cloudpayments.sdk.configuration.CloudpaymentsSDK
import ru.cloudpayments.sdk.configuration.EmailBehavior
import ru.cloudpayments.sdk.configuration.PaymentConfiguration
import ru.cloudpayments.sdk.configuration.PaymentData

/**
 * Bridges Dart to the official CloudPayments Android SDK.
 *
 * Only two things happen here, because only two things need native code:
 * building a card cryptogram with [Card], and showing the SDK's 3-D Secure
 * WebView. Validation, HTTP and orchestration all live in Dart.
 */
class CloudpaymentsSdkPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private companion object {
        const val CHANNEL_NAME = "ru.cloudpayments.flutter/cloudpayments_sdk"
        const val THREE_DS_REQUEST_CODE = 0xCA5D
        const val PAYMENT_FORM_REQUEST_CODE = 0xCA5E
    }

    private var channel: MethodChannel? = null
    private var activityBinding: ActivityPluginBinding? = null

    /** The Dart call waiting on the 3-D Secure screen, if any. */
    private var pendingThreeDsResult: MethodChannel.Result? = null

    /** The Dart call waiting on the ready-made payment form, if any. */
    private var pendingFormResult: MethodChannel.Result? = null

    // --- FlutterPlugin --------------------------------------------------------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).apply {
            setMethodCallHandler(this@CloudpaymentsSdkPlugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // The isolate is going away, so no result can ever be delivered. This
        // is the only place it is safe to abandon a pending call — the host
        // activity coming and going is not, because a cached engine outlives
        // it and the real 3-D Secure result still arrives afterwards.
        finishPendingThreeDs(
            mapOf(
                "status" to CloudpaymentsThreeDsActivity.STATUS_FAILURE,
                "message" to
                    "The Flutter engine was detached before 3-D Secure finished.",
            )
        )
        finishPendingForm(mapOf("status" to "closed"))
        channel?.setMethodCallHandler(null)
        channel = null
    }

    // --- ActivityAware --------------------------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        attach(binding)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        attach(binding)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detach()
    }

    override fun onDetachedFromActivity() {
        // Deliberately does not answer a pending 3-D Secure call.
        //
        // With a cached engine (FlutterActivity.withCachedEngine, or an
        // add-to-app FlutterFragment) the engine — and this plugin instance —
        // outlives the host activity. Reporting "cancelled" here would settle
        // the Dart future while the cardholder is still on the issuer's page,
        // and the genuine result that arrives afterwards would be dropped,
        // losing a payment the issuer had already authenticated.
        //
        // The pending call is kept; onAttachedToActivity re-registers the
        // listener and the real onActivityResult completes it.
        detach()
    }

    private fun attach(binding: ActivityPluginBinding) {
        detach()
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    private fun detach() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
    }

    // --- MethodCallHandler ----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createCryptogram" -> createCryptogram(call, result)
            "show3ds" -> showThreeDs(call, result)
            "presentPaymentForm" -> presentPaymentForm(call, result)
            "nativeSdkVersion" -> result.success(BuildConfig.CLOUDPAYMENTS_SDK_VERSION)
            else -> result.notImplemented()
        }
    }

    private fun createCryptogram(call: MethodCall, result: MethodChannel.Result) {
        val cardNumber = call.argument<String>("cardNumber")
        val expiryDate = call.argument<String>("expiryDate")
        val cvv = call.argument<String>("cvv")
        val publicId = call.argument<String>("publicId")
        val publicKey = call.argument<String>("publicKey")
        val keyVersion = call.argument<Int>("keyVersion")

        if (cardNumber.isNullOrEmpty() || expiryDate.isNullOrEmpty() ||
            cvv.isNullOrEmpty() || publicId.isNullOrEmpty() ||
            publicKey.isNullOrEmpty() || keyVersion == null
        ) {
            result.error(
                "invalid_arguments",
                "createCryptogram needs cardNumber, expiryDate, cvv, publicId, " +
                    "publicKey and keyVersion.",
                null,
            )
            return
        }

        try {
            val cryptogram = Card.createHexPacketFromData(
                cardNumber,
                expiryDate,
                cvv,
                publicId,
                publicKey,
                keyVersion,
            )
            if (cryptogram.isNullOrEmpty()) {
                // The SDK returns null rather than explaining itself; the input
                // has already been validated in Dart, so a bad public key is
                // the likely cause.
                result.error(
                    "cryptogram_failed",
                    "The CloudPayments SDK could not encrypt the card. Check that " +
                        "the card details are valid and the public key is current.",
                    null,
                )
            } else {
                result.success(cryptogram)
            }
        } catch (e: Exception) {
            // Deliberately broad: Card throws half a dozen checked crypto
            // exceptions, and none of them should ever crash the host app.
            result.error(
                "cryptogram_failed",
                e.message ?: e::class.java.simpleName,
                null,
            )
        }
    }

    private fun showThreeDs(call: MethodCall, result: MethodChannel.Result) {
        val activity: Activity? = activityBinding?.activity
        if (activity == null) {
            result.error(
                "no_activity",
                "3-D Secure needs a foreground Activity, and the plugin is not " +
                    "attached to one.",
                null,
            )
            return
        }
        if (pendingThreeDsResult != null) {
            result.error(
                "already_running",
                "A 3-D Secure screen is already open.",
                null,
            )
            return
        }

        val acsUrl = call.argument<String>("acsUrl")
        val paReq = call.argument<String>("paReq")
        val md = call.argument<String>("md")
        if (acsUrl.isNullOrEmpty() || paReq.isNullOrEmpty() || md.isNullOrEmpty()) {
            result.error(
                "invalid_arguments",
                "show3ds needs acsUrl, paReq and md.",
                null,
            )
            return
        }

        // Since Android 10 a background process that calls
        // startActivityForResult is not refused with an exception — the start
        // is silently aborted and only logged. Without this check the call
        // below would appear to succeed, no result would ever arrive, and
        // every later show3ds would answer "already_running" for the rest of
        // the process's life.
        if (!isInForeground()) {
            result.error(
                "not_foreground",
                "The app is in the background, so Android will not let the " +
                    "3-D Secure screen open. Retry once the app is visible.",
                null,
            )
            return
        }

        pendingThreeDsResult = result
        try {
            activity.startActivityForResult(
                CloudpaymentsThreeDsActivity.newIntent(activity, acsUrl, paReq, md),
                THREE_DS_REQUEST_CODE,
            )
        } catch (e: Exception) {
            pendingThreeDsResult = null
            result.error(
                "three_ds_failed",
                "Could not open the 3-D Secure screen: ${e.message}",
                null,
            )
        }
    }

    // --- the ready-made payment form ------------------------------------------

    private fun presentPaymentForm(call: MethodCall, result: MethodChannel.Result) {
        val activity: Activity? = activityBinding?.activity
        if (activity == null) {
            result.error(
                "no_activity",
                "The payment form needs a foreground Activity, and the plugin " +
                    "is not attached to one.",
                null,
            )
            return
        }
        if (pendingFormResult != null) {
            result.error("already_running", "The payment form is already open.", null)
            return
        }
        if (!isInForeground()) {
            result.error(
                "not_foreground",
                "The app is in the background, so Android will not let the " +
                    "payment form open. Retry once the app is visible.",
                null,
            )
            return
        }

        val publicId = call.argument<String>("publicId")
        val amount = call.argument<String>("amount")
        if (publicId.isNullOrEmpty() || amount.isNullOrEmpty()) {
            result.error(
                "invalid_arguments",
                "presentPaymentForm needs publicId and amount.",
                null,
            )
            return
        }

        val configuration = try {
            PaymentConfiguration(
                publicId = publicId,
                paymentData = buildPaymentData(call, amount),
                emailBehavior = when (call.argument<String>("emailBehavior")) {
                    "REQUIRED" -> EmailBehavior.REQUIRED
                    "HIDDEN" -> EmailBehavior.HIDDEN
                    else -> EmailBehavior.OPTIONAL
                },
                useDualMessagePayment = call.argument<Boolean>("twoStage") ?: false,
                paymentMethodSequence = ArrayList(
                    call.argument<List<String>>("methodOrder") ?: emptyList(),
                ),
                singlePaymentMode = call.argument<String>("singleMethod"),
                showResultScreenForSinglePaymentMode =
                    call.argument<Boolean>("showResultScreen") ?: true,
                saveCardForSinglePaymentMode =
                    call.argument<Boolean>("saveCardInSingleMethodMode"),
                testMode = call.argument<Boolean>("testMode") ?: false,
            )
        } catch (e: Exception) {
            result.error(
                "invalid_arguments",
                "Could not build the payment configuration: ${e.message}",
                null,
            )
            return
        }

        pendingFormResult = result
        try {
            activity.startActivityForResult(
                CloudpaymentsSDK.getInstance().getStartIntent(activity, configuration),
                PAYMENT_FORM_REQUEST_CODE,
            )
        } catch (e: Exception) {
            pendingFormResult = null
            result.error(
                "form_failed",
                "Could not open the payment form: ${e.message}",
                null,
            )
        }
    }

    private fun buildPaymentData(call: MethodCall, amount: String): PaymentData {
        val payer = call.argument<Map<String, Any?>>("payer")?.let {
            PaymentDataPayer(
                firstName = it["FirstName"] as? String,
                lastName = it["LastName"] as? String,
                middleName = it["MiddleName"] as? String,
                birthDay = it["Birth"] as? String,
                address = it["Address"] as? String,
                street = it["Street"] as? String,
                city = it["City"] as? String,
                country = it["Country"] as? String,
                phone = it["Phone"] as? String,
                postcode = it["Postcode"] as? String,
            )
        }

        val recurrent = call.argument<Map<String, Any?>>("recurrent")?.let {
            CPRecurrent(
                interval = it["interval"] as? String ?: "Month",
                period = (it["period"] as? Number)?.toInt() ?: 1,
                maxPeriods = (it["maxPeriods"] as? Number)?.toInt(),
                startDate = it["startDate"] as? String,
                amount = (it["amount"] as? Number)?.toDouble(),
                // The SDK's property is customerReceipt but it serialises as
                // "receipt", which is the name CloudPayments now expects.
                @Suppress("UNCHECKED_CAST")
                customerReceipt = it["receipt"] as? Map<String, Any?>,
            )
        }

        @Suppress("UNCHECKED_CAST")
        val receipt = call.argument<Map<String, Any?>>("receipt")

        return PaymentData(
            amount = amount,
            currency = call.argument<String>("currency") ?: "RUB",
            externalId = call.argument<String>("invoiceId"),
            description = call.argument<String>("description"),
            accountId = call.argument<String>("accountId"),
            email = call.argument<String>("email"),
            payer = payer,
            recurrent = recurrent,
            receipt = receipt,
            jsonData = call.argument<String>("jsonData"),
        )
    }

    private fun finishPendingForm(payload: Map<String, Any?>) {
        val result = pendingFormResult ?: return
        pendingFormResult = null
        result.success(payload)
    }

    /** Whether this process is foreground enough to be allowed to start an Activity. */
    private fun isInForeground(): Boolean {
        val state = ActivityManager.RunningAppProcessInfo()
        ActivityManager.getMyMemoryState(state)
        return state.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    }

    // --- ActivityResultListener -----------------------------------------------

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == PAYMENT_FORM_REQUEST_CODE) {
            finishPendingForm(readFormResult(resultCode, data))
            return true
        }
        if (requestCode != THREE_DS_REQUEST_CODE) return false

        val payload: Map<String, Any?> = if (resultCode == Activity.RESULT_OK && data != null) {
            buildMap<String, Any?> {
                put(
                    "status",
                    data.getStringExtra(CloudpaymentsThreeDsActivity.EXTRA_STATUS)
                        ?: CloudpaymentsThreeDsActivity.STATUS_FAILURE,
                )
                data.getStringExtra(CloudpaymentsThreeDsActivity.EXTRA_MD)
                    ?.let { put("md", it) }
                data.getStringExtra(CloudpaymentsThreeDsActivity.EXTRA_PA_RES)
                    ?.let { put("paRes", it) }
                data.getStringExtra(CloudpaymentsThreeDsActivity.EXTRA_MESSAGE)
                    ?.let { put("message", it) }
                data.getStringExtra(CloudpaymentsThreeDsActivity.EXTRA_HTML)
                    ?.let { put("html", it) }
            }
        } else {
            // The screen was dismissed by the system or by a back gesture
            // without ever reporting a result.
            mapOf("status" to CloudpaymentsThreeDsActivity.STATUS_CANCELLED)
        }

        finishPendingThreeDs(payload)
        return true
    }

    /**
     * Reads the form's answer, mirroring the SDK's own CloudPaymentsIntentSender.
     *
     * A missing TransactionStatus means the user backed out — the SDK only sets
     * it when a payment was actually attempted.
     */
    @Suppress("DEPRECATION")
    private fun readFormResult(resultCode: Int, data: Intent?): Map<String, Any?> {
        if (resultCode != Activity.RESULT_OK || data == null) {
            return mapOf("status" to "closed")
        }

        val transactionId =
            data.getLongExtra(CloudpaymentsSDK.IntentKeys.TransactionId.name, 0L)
        val status = data.getSerializableExtra(
            CloudpaymentsSDK.IntentKeys.TransactionStatus.name,
        ) as? CloudpaymentsSDK.TransactionStatus
        val reasonCode =
            data.getIntExtra(CloudpaymentsSDK.IntentKeys.TransactionReasonCode.name, 0)

        return when (status) {
            CloudpaymentsSDK.TransactionStatus.Succeeded -> mapOf(
                "status" to "succeeded",
                "transactionId" to transactionId,
            )
            CloudpaymentsSDK.TransactionStatus.Failed -> mapOf(
                "status" to "failed",
                "transactionId" to transactionId,
                "reasonCode" to reasonCode,
            )
            null -> mapOf("status" to "closed")
        }
    }

    private fun finishPendingThreeDs(payload: Map<String, Any?>) {
        val result = pendingThreeDsResult ?: return
        pendingThreeDsResult = null
        result.success(payload)
    }
}
