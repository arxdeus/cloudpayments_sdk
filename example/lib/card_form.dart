import 'package:cloudpayments_sdk/cloudpayments_sdk.dart';
import 'package:flutter/material.dart';

/// A card entry form with live formatting, payment-system detection and
/// validation — all of it running locally in Dart.
///
/// The card details never leave this widget except as a [CardData] handed
/// straight to the SDK.
class CardForm extends StatefulWidget {
  /// Creates the card form.
  const CardForm({super.key});

  @override
  State<CardForm> createState() => CardFormState();
}

/// The state of a [CardForm]. Call [readCard] to collect what the user typed.
class CardFormState extends State<CardForm> {
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  final _holder = TextEditingController();

  CardSystem _system = CardSystem.unknown;

  @override
  void initState() {
    super.initState();
    _number.addListener(() {
      final detected = CardUtils.detectSystem(_number.text);
      if (detected != _system) setState(() => _system = detected);
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    _cvv.dispose();
    _holder.dispose();
    super.dispose();
  }

  /// The card the user entered.
  CardData readCard() => CardData(
        number: _number.text,
        expiryDate: _expiry.text,
        cvv: _cvv.text,
        holderName: _holder.text.isEmpty ? null : _holder.text,
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _number,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.creditCardNumber],
            inputFormatters: const [CardNumberInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Card number',
              border: const OutlineInputBorder(),
              suffixIcon: _system == CardSystem.unknown
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          _system.wireName,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
            ),
            validator: (value) => CardUtils.isValidNumber(value ?? '')
                ? null
                : 'Check the card number',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _expiry,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [ExpiryDateInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'MM/YY',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => CardUtils.isValidExpiryDate(value ?? '')
                      ? null
                      : 'Expired or invalid',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _cvv,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  inputFormatters: [
                    CvvInputFormatter(cardNumber: () => _number.text),
                  ],
                  decoration: InputDecoration(
                    labelText:
                        _system == CardSystem.americanExpress ? 'CID' : 'CVV',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => CardUtils.isValidCvv(value ?? '',
                          cardNumber: _number.text)
                      ? null
                      : 'Check the code',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _holder,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Cardholder name (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      );
}
