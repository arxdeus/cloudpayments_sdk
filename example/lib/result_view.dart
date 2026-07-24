import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/material.dart';

/// Renders the outcome of a payment.
///
/// The `switch` over [PaymentResult] is exhaustive — the compiler enforces
/// that every outcome is handled, which is the point of modelling them as a
/// sealed hierarchy rather than as exceptions.
class ResultView extends StatelessWidget {
  /// Creates the result panel.
  const ResultView({
    required this.result,
    required this.formResult,
    required this.error,
    super.key,
  });

  /// The outcome of the last custom-form payment, if there was one.
  final PaymentResult? result;

  /// The outcome of the last ready-made-form payment, if there was one.
  final PaymentFormResult? formResult;

  /// The error the last payment threw, if it threw one.
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (error != null) {
      return _Panel(
        colour: theme.colorScheme.errorContainer,
        icon: Icons.error_outline,
        title: 'Something went wrong',
        body: switch (error) {
          CloudpaymentsNetworkException() =>
            'Could not reach CloudPayments. Check the connection and try again.',
          CloudpaymentsCryptogramException(:final message) => message,
          CloudpaymentsConfigurationException(:final message) => message,
          CloudpaymentsApiException(:final message) => message,
          _ => error.toString(),
        },
      );
    }

    final form = formResult;
    if (form != null) {
      return switch (form) {
        FormPaymentSucceeded(:final transactionId) => _Panel(
            colour: theme.colorScheme.primaryContainer,
            icon: Icons.check_circle_outline,
            title: 'Paid through the CloudPayments form',
            body: [
              'Transaction #$transactionId',
              'The form reports only the transaction id. Fetch the rest from '
                  'your backend or the pay webhook.',
            ].join('\n'),
          ),
        FormPaymentFailed(:final reasonCode, :final message) => _Panel(
            colour: theme.colorScheme.errorContainer,
            icon: Icons.credit_card_off_outlined,
            title: 'Not completed',
            body: [
              message ?? 'The payment did not go through.',
              if (reasonCode != null) 'Reason code $reasonCode',
            ].join('\n'),
          ),
        FormPaymentClosed() => _Panel(
            colour: theme.colorScheme.surfaceContainerHighest,
            icon: Icons.cancel_outlined,
            title: 'Closed',
            body: 'The form was dismissed. No money moved.',
          ),
      };
    }

    final payment = result;
    if (payment == null) return const SizedBox.shrink();

    return switch (payment) {
      PaymentSuccess(:final transaction) => _Panel(
          colour: theme.colorScheme.primaryContainer,
          icon: Icons.check_circle_outline,
          title: 'Paid',
          body: [
            'Transaction #${transaction.transactionId}',
            if (transaction.status != TransactionStatus.unknown)
              'Status: ${transaction.rawStatus}',
            if (transaction.maskedCard != null)
              'Card: ${transaction.maskedCard}',
            if (transaction.token != null)
              'Saved-card token: ${transaction.token}',
            if (transaction.status == TransactionStatus.unknown)
              'The 3-D Secure callback confirms only that the payment went '
                  'through. Fetch the full transaction from your backend.',
          ].join('\n'),
        ),
      PaymentDeclined(:final cardHolderMessage, :final reasonCode) => _Panel(
          colour: theme.colorScheme.errorContainer,
          icon: Icons.credit_card_off_outlined,
          title: 'Declined',
          body: [
            cardHolderMessage ?? 'The issuer refused the payment.',
            if (reasonCode != null) 'Reason code $reasonCode',
          ].join('\n'),
        ),
      PaymentCancelled() => _Panel(
          colour: theme.colorScheme.surfaceContainerHighest,
          icon: Icons.cancel_outlined,
          title: 'Cancelled',
          body: 'The 3-D Secure screen was closed before authentication '
              'finished. No money moved.',
        ),
      PaymentFailure(:final message, :final reasonCode) => _Panel(
          colour: theme.colorScheme.errorContainer,
          icon: Icons.warning_amber_outlined,
          title: 'Not completed',
          body: [
            message,
            if (reasonCode != null) 'Reason code $reasonCode',
          ].join('\n'),
        ),
      // pay() resolves 3-D Secure itself, so this is unreachable from the
      // example — it exists for code that drives CloudpaymentsApiClient
      // directly.
      PaymentRequiresThreeDs() => _Panel(
          colour: theme.colorScheme.surfaceContainerHighest,
          icon: Icons.lock_outline,
          title: 'Authentication required',
          body: 'The issuer wants the cardholder to pass 3-D Secure.',
        ),
    };
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.colour,
    required this.icon,
    required this.title,
    required this.body,
  });

  final Color colour;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body),
                ],
              ),
            ),
          ],
        ),
      );
}
