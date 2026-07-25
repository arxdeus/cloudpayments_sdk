import 'package:meta/meta.dart';

/// The taxation system reported on a fiscal receipt (54-ФЗ).
enum TaxationSystem {
  /// Общая (ОСН).
  general(0),

  /// Упрощённая, доход (УСН доход).
  simplifiedIncome(1),

  /// Упрощённая, доход минус расход (УСН доход-расход).
  simplifiedIncomeMinusExpense(2),

  /// Единый налог на вменённый доход (ЕНВД).
  unifiedImputedIncome(3),

  /// Единый сельскохозяйственный налог (ЕСХН).
  unifiedAgricultural(4),

  /// Патентная система (ПСН).
  patent(5);

  const TaxationSystem(this.code);

  /// The numeric code sent in `taxationSystem`.
  final int code;
}

/// VAT rate applied to a receipt line.
enum VatRate {
  /// Без НДС.
  none(null),

  /// НДС 0%.
  vat0(0),

  /// НДС 5%.
  vat5(5),

  /// НДС 7%.
  vat7(7),

  /// НДС 10%.
  vat10(10),

  /// НДС 20%.
  vat20(20),

  /// НДС по расчётной ставке 105 (5/105).
  vat105(105),

  /// НДС по расчётной ставке 107 (7/107).
  vat107(107),

  /// НДС по расчётной ставке 110 (10/110).
  vat110(110),

  /// НДС по расчётной ставке 120 (20/120).
  vat120(120);

  const VatRate(this.code);

  /// The value sent in `vat`; `null` means the line is not subject to VAT.
  final int? code;
}

/// A single line on a fiscal receipt.
@immutable
class ReceiptItem {
  /// Creates a receipt line.
  ///
  /// [amount] defaults to `price * quantity` when omitted.
  const ReceiptItem({
    required this.label,
    required this.price,
    this.quantity = 1,
    double? amount,
    this.vat = VatRate.none,
    this.method,
    this.object,
    this.measurementUnit,
    this.excise,
    this.productCode,
    this.countryCode,
    this.customsDeclarationNumber,
  }) : _amount = amount;

  /// Product or service name printed on the receipt.
  final String label;

  /// Unit price.
  final double price;

  /// Quantity sold.
  final double quantity;

  final double? _amount;

  /// Line total. Defaults to `price * quantity`.
  double get amount => _amount ?? price * quantity;

  /// VAT rate for this line.
  final VatRate vat;

  /// Признак способа расчёта (`method`), 0..7.
  final int? method;

  /// Признак предмета расчёта (`object`), 0..19.
  final int? object;

  /// Unit of measurement, e.g. `шт`.
  final String? measurementUnit;

  /// Excise duty amount.
  final double? excise;

  /// Nomenclature code (маркировка).
  final String? productCode;

  /// Country of origin code.
  final String? countryCode;

  /// Customs declaration number.
  final String? customsDeclarationNumber;

  /// Serialises the line to its API shape.
  @useResult
  Map<String, dynamic> toJson() => <String, dynamic>{
        'label': label,
        'price': price,
        'quantity': quantity,
        'amount': amount,
        'vat': vat.code,
        if (method != null) 'method': method,
        if (object != null) 'object': object,
        if (measurementUnit != null) 'measurementUnit': measurementUnit,
        if (excise != null) 'excise': excise,
        if (productCode != null) 'productCode': productCode,
        if (countryCode != null) 'countryCode': countryCode,
        if (customsDeclarationNumber != null)
          'customsDeclarationNumber': customsDeclarationNumber,
      };
}

/// How the receipt total is split across payment methods.
@immutable
class ReceiptAmounts {
  /// Creates a payment split. Fields left at zero are omitted.
  const ReceiptAmounts({
    this.electronic = 0,
    this.advancePayment = 0,
    this.credit = 0,
    this.provision = 0,
  });

  /// Paid electronically.
  final double electronic;

  /// Paid from a previous advance.
  final double advancePayment;

  /// Paid on credit.
  final double credit;

  /// Paid by counter-provision.
  final double provision;

  /// Serialises the split to its API shape.
  @useResult
  Map<String, dynamic> toJson() => <String, dynamic>{
        'electronic': electronic,
        'advancePayment': advancePayment,
        'credit': credit,
        'provision': provision,
      };
}

/// A fiscal receipt (кассовый чек) to be registered alongside the payment.
///
/// CloudPayments carries it in the request's `JsonData` under
/// `CloudPayments.CustomerReceipt`; [Receipt.toJsonData] builds that wrapper
/// for you.
@immutable
class Receipt {
  /// Creates a receipt.
  const Receipt({
    required this.items,
    this.taxationSystem,
    this.email,
    this.phone,
    this.customerInfo,
    this.customerInn,
    this.isBso = false,
    this.amounts,
    this.calculationPlace,
  });

  /// Receipt lines. Must not be empty.
  final List<ReceiptItem> items;

  /// Taxation system of the merchant.
  final TaxationSystem? taxationSystem;

  /// Where to send the electronic receipt.
  final String? email;

  /// Where to send the electronic receipt by SMS.
  final String? phone;

  /// Buyer's name (for receipts that require it).
  final String? customerInfo;

  /// Buyer's INN.
  final String? customerInn;

  /// Whether this is a БСО rather than a receipt.
  final bool isBso;

  /// Split of the total across payment methods.
  final ReceiptAmounts? amounts;

  /// Место расчётов, e.g. your site URL.
  final String? calculationPlace;

  /// The sum of all line totals.
  double get total => items.fold(0, (sum, item) => sum + item.amount);

  /// Serialises the receipt to its `CustomerReceipt` shape.
  @useResult
  Map<String, dynamic> toJson() => <String, dynamic>{
        'Items': items.map((item) => item.toJson()).toList(),
        if (taxationSystem != null) 'taxationSystem': taxationSystem!.code,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (customerInfo != null) 'customerInfo': customerInfo,
        if (customerInn != null) 'customerInn': customerInn,
        if (isBso) 'isBso': isBso,
        if (calculationPlace != null) 'calculationPlace': calculationPlace,
        'amounts': (amounts ?? ReceiptAmounts(electronic: total)).toJson(),
      };

  /// Wraps the receipt in the `JsonData` envelope CloudPayments expects,
  /// merging it into [existing] if given.
  @useResult
  Map<String, dynamic> toJsonData([Map<String, dynamic>? existing]) {
    final data = <String, dynamic>{...?existing};
    final cloudPayments = <String, dynamic>{
      ...?(data['CloudPayments'] as Map<String, dynamic>?),
      'CustomerReceipt': toJson(),
    };
    data['CloudPayments'] = cloudPayments;
    return data;
  }
}
