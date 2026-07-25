import 'package:meta/meta.dart';

import 'receipt.dart';

/// How often a subscription charges.
enum RecurrentInterval {
  /// Every [CloudpaymentsRecurrent.period] days.
  day('Day'),

  /// Every [CloudpaymentsRecurrent.period] weeks.
  week('Week'),

  /// Every [CloudpaymentsRecurrent.period] months.
  month('Month');

  const RecurrentInterval(this.wireName);

  /// The value CloudPayments expects in `interval`.
  final String wireName;
}

/// Instructions to create a subscription alongside a payment.
///
/// This is how recurring payments are set up from a client: you send it with
/// the *first* payment, and CloudPayments charges every following period
/// itself, server-side, on schedule. Your app is not involved after that, and
/// no API secret is needed.
///
/// The subscription is bound to the payer, so
/// [PaymentDetails.accountId] is required on the payment that creates it.
///
/// ```dart
/// await cp.presentPaymentForm(
///   details: const PaymentDetails(
///     amount: 499,
///     accountId: 'user-42',          // required for a subscription
///     email: 'user@example.com',
///     description: 'Подписка «Про»',
///   ),
///   recurrent: const CloudpaymentsRecurrent(
///     interval: RecurrentInterval.month,
///     period: 1,
///   ),
/// );
/// ```
///
/// What you cannot do from the app: charge off-schedule, or change and cancel
/// the subscription. Those need the API secret and belong on your backend.
@immutable
class CloudpaymentsRecurrent {
  /// Creates subscription instructions.
  const CloudpaymentsRecurrent({
    required this.interval,
    required this.period,
    this.amount,
    this.startDate,
    this.maxPeriods,
    this.receipt,
  });

  /// The unit of the charging cycle.
  final RecurrentInterval interval;

  /// How many [interval]s between charges. `1` with
  /// [RecurrentInterval.month] means monthly.
  final int period;

  /// What to charge each period. Defaults to the amount of the first payment.
  ///
  /// Useful when the first payment differs — a trial, or a discounted first
  /// month.
  final num? amount;

  /// When the first *recurring* charge happens, as `yyyy-MM-dd`. Omit to start
  /// one [period] after the initial payment.
  ///
  /// Setting it is the practical way to test a subscription without waiting:
  /// point it at tomorrow with a daily interval.
  final String? startDate;

  /// How many times to charge in total. Omit for an open-ended subscription.
  final int? maxPeriods;

  /// The fiscal receipt to issue for each recurring charge (54-ФЗ).
  final Receipt? receipt;

  /// Serialises to the shape both native SDKs take.
  ///
  /// The receipt key is `receipt`, not `customerReceipt` — CloudPayments
  /// renamed it, and both 2.x SDKs send the new name.
  @useResult
  Map<String, dynamic> toJson() => <String, dynamic>{
        'interval': interval.wireName,
        'period': period,
        if (amount != null) 'amount': amount,
        if (startDate != null) 'startDate': startDate,
        if (maxPeriods != null) 'maxPeriods': maxPeriods,
        if (receipt != null) 'receipt': receipt!.toJson(),
      };

  @override
  String toString() =>
      'CloudpaymentsRecurrent(every $period ${interval.wireName})';
}
