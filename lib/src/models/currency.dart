import 'package:meta/meta.dart';

/// Currencies CloudPayments accepts, as ISO 4217 alphabetic codes.
///
/// This list is the union of the currencies the official iOS SDK declares and
/// those the public API documents. Whether a given currency actually works
/// depends on what your account is enabled for. If you need a code that is not
/// here, pass it as a raw string — every request model accepts one.
enum Currency {
  /// Russian rouble.
  rub('RUB'),

  /// Euro.
  eur('EUR'),

  /// US dollar.
  usd('USD'),

  /// Pound sterling.
  gbp('GBP'),

  /// Ukrainian hryvnia.
  uah('UAH'),

  /// Belarusian rouble.
  byn('BYN'),

  /// Belarusian rouble, pre-2016 denomination. Legacy; prefer [byn].
  byr('BYR'),

  /// Kazakhstani tenge.
  kzt('KZT'),

  /// Azerbaijani manat.
  azn('AZN'),

  /// Swiss franc.
  chf('CHF'),

  /// Czech koruna.
  czk('CZK'),

  /// Canadian dollar.
  cad('CAD'),

  /// Polish zloty.
  pln('PLN'),

  /// Swedish krona.
  sek('SEK'),

  /// Turkish lira.
  tryy('TRY'),

  /// Chinese yuan.
  cny('CNY'),

  /// Indian rupee.
  inr('INR'),

  /// Brazilian real.
  brl('BRL'),

  /// South African rand.
  zar('ZAR'),

  /// Uzbekistani sum.
  uzs('UZS'),

  /// Bulgarian lev, as spelled by the CloudPayments SDKs.
  bgl('BGL');

  const Currency(this.code);

  /// The ISO 4217 alphabetic code sent to and received from the API.
  final String code;

  /// Parses an ISO 4217 code, case-insensitively. Returns `null` for codes
  /// this enum does not cover.
  @useResult
  static Currency? fromCode(String? code) {
    if (code == null) return null;
    final upper = code.toUpperCase();
    for (final currency in Currency.values) {
      if (currency.code == upper) return currency;
    }
    return null;
  }
}

/// The language CloudPayments uses for cardholder-facing messages and
/// notification emails, sent as `CultureName`.
enum CultureName {
  /// Russian.
  ruRu('ru-RU'),

  /// English (US).
  enUs('en-US'),

  /// Latvian.
  lv('lv'),

  /// Azerbaijani.
  az('az'),

  /// Kazakh.
  kk('kk'),

  /// Ukrainian.
  uk('uk'),

  /// Polish.
  pl('pl');

  const CultureName(this.code);

  /// The value sent in `CultureName`.
  final String code;
}
