import 'dart:async';

import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/material.dart';

import 'card_form.dart';
import 'result_view.dart';

void main() => runApp(const CloudpaymentsExampleApp());

/// A one-screen checkout that runs the whole CloudPayments cycle.
class CloudpaymentsExampleApp extends StatelessWidget {
  /// Creates the example app.
  const CloudpaymentsExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CloudPayments SDK example',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2A7FFF),
          useMaterial3: true,
        ),
        home: const CheckoutScreen(),
      );
}

/// The checkout screen.
///
/// Two ways to take the same payment:
///
/// * **the ready-made form** — CloudPayments' own UI, which also brings СБП,
///   T‑Pay, SberPay and Долями with it. One call, nothing to build.
/// * **your own form** — the card fields below, encrypted through the native
///   SDK and charged through the API, with 3-D Secure in a native screen.
class CheckoutScreen extends StatefulWidget {
  /// Creates the checkout screen.
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  /// The Public ID of the CloudPayments demo merchant. Replace it with your
  /// own from https://merchant.cloudpayments.ru/ — it is not a secret.
  static const String _publicId = 'test_api_00000000000000000000002';

  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController(text: '10.00');
  final _email = TextEditingController();
  final _cardKey = GlobalKey<CardFormState>();

  late final CloudpaymentsSdk _cloudpayments;

  bool _twoStage = false;
  bool _subscribe = false;
  bool _busy = false;
  PaymentResult? _result;
  PaymentFormResult? _formResult;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _cloudpayments = CloudpaymentsSdk(publicId: _publicId);
    // Fetch the RSA key now so the first payment does not wait for it. Only
    // the custom-form path needs it; the ready-made form fetches its own.
    unawaited(_cloudpayments.warmUp());
  }

  @override
  void dispose() {
    _cloudpayments.dispose();
    _amount.dispose();
    _email.dispose();
    super.dispose();
  }

  num? get _parsedAmount => num.tryParse(_amount.text.replaceAll(',', '.'));

  PaymentDetails get _details => PaymentDetails(
        amount: _parsedAmount ?? 0,
        invoiceId: 'EXAMPLE-${DateTime.now().millisecondsSinceEpoch}',
        description: 'cloudpayments_sdk example payment',
        email: _email.text.isEmpty ? null : _email.text,
        // A subscription is bound to the payer, so it needs an accountId.
        accountId: _email.text.isEmpty ? 'example-user' : _email.text,
        cultureName: CultureName.ruRu,
      );

  /// A subscription created together with the first payment.
  ///
  /// Nothing else is needed: CloudPayments charges every following period
  /// itself, server-side. Daily is deliberate — it is the only way to watch a
  /// real recurring charge happen without waiting a month.
  CloudpaymentsRecurrent? get _recurrent => _subscribe
      ? const CloudpaymentsRecurrent(
          interval: RecurrentInterval.day,
          period: 1,
        )
      : null;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _result = null;
      _formResult = null;
      _error = null;
    });
    try {
      await action();
    } on CloudpaymentsException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _payWithReadyMadeForm() => _run(() async {
        if (_parsedAmount == null || _parsedAmount! <= 0) {
          setState(() => _error = 'Enter an amount greater than zero');
          return;
        }
        final result = await _cloudpayments.presentPaymentForm(
          details: _details,
          recurrent: _recurrent,
          options: PaymentFormOptions(twoStage: _twoStage, testMode: true),
        );
        if (mounted) setState(() => _formResult = result);
      });

  Future<void> _payWithOwnForm() => _run(() async {
        if (!(_formKey.currentState?.validate() ?? false)) return;
        final card = _cardKey.currentState?.readCard();
        if (card == null) return;

        final result = await _cloudpayments.pay(
          card: card,
          details: _details.copyWithRecurrent(_recurrent),
          twoStage: _twoStage,
        );
        if (mounted) setState(() => _result = result);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('CloudPayments checkout')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount, RUB',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = num.tryParse(
                    (value ?? '').replaceAll(',', '.'),
                  );
                  if (amount == null || amount <= 0) {
                    return 'Enter an amount greater than zero';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email for the receipt (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _twoStage,
                onChanged: (value) => setState(() => _twoStage = value),
                title: const Text('Two-stage payment'),
                subtitle: const Text(
                  'Hold the funds instead of capturing them. Capturing needs '
                  'the API secret, so it happens on your backend.',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _subscribe,
                onChanged: (value) => setState(() => _subscribe = value),
                title: const Text('Also start a daily subscription'),
                subtitle: const Text(
                  'CloudPayments charges every following day by itself. Daily '
                  'rather than monthly so you can actually watch it happen.',
                ),
              ),
              const SizedBox(height: 16),
              Text('CloudPayments’ own form',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'One call. Card entry, 3-D Secure, СБП, T‑Pay, SberPay and '
                'Долями — all handled by the native SDK.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _payWithReadyMadeForm,
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: Text(
                    _twoStage ? 'Hold with the form' : 'Pay with the form'),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Divider(),
              ),
              Text('Your own form', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Card fields you control. The number never leaves this screen '
                'except as a cryptogram.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              CardForm(key: _cardKey),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _payWithOwnForm,
                child: Text(_twoStage ? 'Hold funds' : 'Pay'),
              ),
              const SizedBox(height: 24),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else
                ResultView(
                  result: _result,
                  formResult: _formResult,
                  error: _error,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on PaymentDetails {
  /// The example reuses one [PaymentDetails] for both paths; the low-level
  /// path carries the subscription inside the request itself.
  PaymentDetails copyWithRecurrent(CloudpaymentsRecurrent? recurrent) =>
      PaymentDetails(
        amount: amount,
        currency: currency,
        invoiceId: invoiceId,
        description: description,
        accountId: accountId,
        email: email,
        cultureName: cultureName,
        recurrent: recurrent,
      );
}
