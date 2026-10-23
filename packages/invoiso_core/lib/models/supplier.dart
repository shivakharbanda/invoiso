// Data Models
class Supplier {
  String id;
  String name;
  String businessName;
  String phone;
  String email;
  String address;
  String gstin;
  String notes;
  DateTime? deletedAt;

  // Vendor spend tracking (null = not set). Only written when set, so the
  // purchase-bill supplier screen, which doesn't know them, can't clear them.
  String? defaultCurrency;

  /// `prepaid` (wallet top-ups), `postpaid` (invoiced), `subscription`.
  String? billingModel;
  String? defaultCategoryId;

  /// Warn when the prepaid wallet balance drops below this.
  double? lowBalanceThreshold;

  Supplier({
    required this.id,
    required this.name,
    this.businessName = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.gstin = '',
    this.notes = '',
    this.deletedAt,
    this.defaultCurrency,
    this.billingModel,
    this.defaultCategoryId,
    this.lowBalanceThreshold,
  });

  // Convert a Map into a Supplier object
  factory Supplier.fromMap(Map<String, dynamic> map) {
    return Supplier(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      businessName: map['business_name'] ?? '',
      phone: map['phone'] ?? '',
      email: map['email'] ?? '',
      address: map['address'] ?? '',
      gstin: map['gstin'] ?? '',
      notes: map['notes'] ?? '',
      deletedAt: map['deleted_at'] != null
          ? DateTime.tryParse(map['deleted_at'] as String)
          : null,
      defaultCurrency: map['default_currency'] as String?,
      billingModel: map['billing_model'] as String?,
      defaultCategoryId: map['default_category_id'] as String?,
      lowBalanceThreshold: (map['low_balance_threshold'] as num?)?.toDouble(),
    );
  }

  // Convert a Supplier object into a Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'business_name': businessName,
      'phone': phone,
      'email': email,
      'address': address,
      'gstin': gstin,
      'notes': notes,
      'deleted_at': deletedAt?.toIso8601String(),
      if (defaultCurrency != null) 'default_currency': defaultCurrency,
      if (billingModel != null) 'billing_model': billingModel,
      if (defaultCategoryId != null) 'default_category_id': defaultCategoryId,
      if (lowBalanceThreshold != null)
        'low_balance_threshold': lowBalanceThreshold,
    };
  }
}
