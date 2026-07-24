/// Payer details sent in the `Payer` object of a payment request.
///
/// Every field is optional, but acquirers apply lower fraud scores when more
/// of them are filled in, and some 3-D Secure 2 flows use them for frictionless
/// authentication.
class Payer {
  /// Creates payer details. All fields are optional.
  const Payer({
    this.firstName,
    this.lastName,
    this.middleName,
    this.birth,
    this.address,
    this.street,
    this.city,
    this.country,
    this.phone,
    this.postcode,
  });

  /// Restores a [Payer] from the `Payer` object of an API response.
  factory Payer.fromJson(Map<String, dynamic> json) => Payer(
        firstName: json['FirstName'] as String?,
        lastName: json['LastName'] as String?,
        middleName: json['MiddleName'] as String?,
        birth: json['Birth'] as String?,
        address: json['Address'] as String?,
        street: json['Street'] as String?,
        city: json['City'] as String?,
        country: json['Country'] as String?,
        phone: json['Phone'] as String?,
        postcode: json['Postcode'] as String?,
      );

  /// Given name.
  final String? firstName;

  /// Family name.
  final String? lastName;

  /// Patronymic.
  final String? middleName;

  /// Date of birth as `yyyy-MM-dd`.
  final String? birth;

  /// Street address.
  final String? address;

  /// Street name.
  final String? street;

  /// City.
  final String? city;

  /// Two-letter ISO 3166-1 alpha-2 country code, e.g. `RU`.
  final String? country;

  /// Phone number.
  final String? phone;

  /// Postal code.
  final String? postcode;

  /// Serialises to the `Payer` object shape, omitting unset fields.
  Map<String, dynamic> toJson() => <String, dynamic>{
        if (firstName != null) 'FirstName': firstName,
        if (lastName != null) 'LastName': lastName,
        if (middleName != null) 'MiddleName': middleName,
        if (birth != null) 'Birth': birth,
        if (address != null) 'Address': address,
        if (street != null) 'Street': street,
        if (city != null) 'City': city,
        if (country != null) 'Country': country,
        if (phone != null) 'Phone': phone,
        if (postcode != null) 'Postcode': postcode,
      };

  /// Whether every field is unset, in which case the object should be omitted
  /// from the request entirely.
  bool get isEmpty => toJson().isEmpty;

  @override
  String toString() => 'Payer(${toJson()})';
}
