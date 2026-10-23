/// Money going out to vendors (GPU cloud, telephony, SaaS, …).
///
/// [entryType] decides how an entry counts:
/// * `topup` — prepaid wallet recharge: cash out, adds to the vendor wallet;
///   not a cost by itself (the usage it pays for is).
/// * `usage` — consumption from a prepaid wallet (minutes, GPU hours): a cost
///   for client/project profitability, draws the wallet down, no cash moves.
/// * `invoice`, `subscription`, `other` — paid directly: both cash out and cost.
class Expense {
  static const typeTopup = 'topup';
  static const typeUsage = 'usage';
  static const typeInvoice = 'invoice';
  static const typeSubscription = 'subscription';
  static const typeOther = 'other';
  static const types = [
    typeTopup,
    typeUsage,
    typeInvoice,
    typeSubscription,
    typeOther,
  ];

  /// Entry types where money actually leaves the bank (cash basis / P&L).
  static const cashTypes = [
    typeTopup,
    typeInvoice,
    typeSubscription,
    typeOther,
  ];

  /// Entry types that are a cost of serving clients (profitability).
  static const costTypes = [
    typeUsage,
    typeInvoice,
    typeSubscription,
    typeOther,
  ];

  /// `gst` (CGST+SGST), `igst`, `rcm` (reverse charge on imported services),
  /// `none`.
  static const taxKinds = ['none', 'gst', 'igst', 'rcm'];

  final String id;
  final String? vendorId;
  final String vendorName;
  final String? categoryId;
  final String entryType;
  final DateTime date;
  final String description;
  final String? referenceNo;

  /// Currency the vendor billed in; [amount] and [taxAmount] are in it.
  final String currencyCode;

  /// Pre-tax amount (for top-ups: the wallet credit).
  final double amount;
  final double taxAmount;
  final String taxKind;

  /// What was actually paid in INR, tax included (bank/card debit — includes
  /// any forex markup). For usage entries, the INR value of what was used.
  final double inrAmount;
  final String? paymentMethod;
  final String? customerId;
  final String? projectId;
  final double? usageQty;
  final String? usageUnit;
  final String? recurringId;
  final String? notes;
  final String? createdBy;
  final DateTime? createdAt;

  /// Number of receipts attached (read-only, filled by list queries).
  final int attachmentCount;

  const Expense({
    required this.id,
    this.vendorId,
    this.vendorName = '',
    this.categoryId,
    required this.entryType,
    required this.date,
    this.description = '',
    this.referenceNo,
    this.currencyCode = 'INR',
    required this.amount,
    this.taxAmount = 0,
    this.taxKind = 'none',
    required this.inrAmount,
    this.paymentMethod,
    this.customerId,
    this.projectId,
    this.usageQty,
    this.usageUnit,
    this.recurringId,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.attachmentCount = 0,
  });

  double get total => amount + taxAmount;

  bool get isCashOut => cashTypes.contains(entryType);

  bool get isCost => costTypes.contains(entryType);

  /// INR per unit of [currencyCode] implied by what was paid.
  double? get impliedRate =>
      currencyCode == 'INR' || total == 0 ? null : inrAmount / total;

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as String,
        vendorId: m['vendor_id'] as String?,
        vendorName: m['vendor_name'] as String? ?? '',
        categoryId: m['category_id'] as String?,
        entryType: m['entry_type'] as String,
        date: DateTime.parse(m['date'] as String),
        description: m['description'] as String? ?? '',
        referenceNo: m['reference_no'] as String?,
        currencyCode: m['currency_code'] as String? ?? 'INR',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        taxAmount: (m['tax_amount'] as num?)?.toDouble() ?? 0,
        taxKind: m['tax_kind'] as String? ?? 'none',
        inrAmount: (m['inr_amount'] as num?)?.toDouble() ?? 0,
        paymentMethod: m['payment_method'] as String?,
        customerId: m['customer_id'] as String?,
        projectId: m['project_id'] as String?,
        usageQty: (m['usage_qty'] as num?)?.toDouble(),
        usageUnit: m['usage_unit'] as String?,
        recurringId: m['recurring_id'] as String?,
        notes: m['notes'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: m['created_at'] == null
            ? null
            : DateTime.tryParse(m['created_at'] as String),
        attachmentCount: (m['attachment_count'] as num?)?.toInt() ?? 0,
      );

  /// Row for the `expenses` table (without the computed attachment count).
  Map<String, dynamic> toMap() => {
        'id': id,
        'vendor_id': vendorId,
        'vendor_name': vendorName,
        'category_id': categoryId,
        'entry_type': entryType,
        'date': date.toIso8601String(),
        'description': description,
        'reference_no': referenceNo,
        'currency_code': currencyCode,
        'amount': amount,
        'tax_amount': taxAmount,
        'tax_kind': taxKind,
        'inr_amount': inrAmount,
        'payment_method': paymentMethod,
        'customer_id': customerId,
        'project_id': projectId,
        'usage_qty': usageQty,
        'usage_unit': usageUnit,
        'recurring_id': recurringId,
        'notes': notes,
        'created_by': createdBy,
        'created_at': createdAt?.toIso8601String(),
      };

  Map<String, dynamic> toJson() =>
      {...toMap(), 'attachment_count': attachmentCount};

  factory Expense.fromJson(Map<String, dynamic> j) => Expense.fromMap(j);
}

class ExpenseCategory {
  final String id;
  final String name;
  final int sortOrder;

  const ExpenseCategory({required this.id, required this.name, this.sortOrder = 0});

  /// Seeded the first time categories are read for a company.
  static const defaults = [
    ExpenseCategory(id: 'cat-gpu', name: 'GPU / Compute', sortOrder: 0),
    ExpenseCategory(id: 'cat-telephony', name: 'Telephony', sortOrder: 1),
    ExpenseCategory(id: 'cat-cloud', name: 'Cloud hosting', sortOrder: 2),
    ExpenseCategory(id: 'cat-saas', name: 'SaaS & tools', sortOrder: 3),
    ExpenseCategory(id: 'cat-domains', name: 'Domains & DNS', sortOrder: 4),
    ExpenseCategory(id: 'cat-other', name: 'Other', sortOrder: 5),
  ];

  factory ExpenseCategory.fromMap(Map<String, dynamic> m) => ExpenseCategory(
        id: m['id'] as String,
        name: m['name'] as String,
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'sort_order': sortOrder};
}

/// A piece of work costs can be tagged to, optionally for a client.
class Project {
  final String id;
  final String name;
  final String? customerId;
  final String? notes;
  final bool archived;

  const Project({
    required this.id,
    required this.name,
    this.customerId,
    this.notes,
    this.archived = false,
  });

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id'] as String,
        name: m['name'] as String,
        customerId: m['customer_id'] as String?,
        notes: m['notes'] as String?,
        archived: (m['archived'] as num?)?.toInt() == 1,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'customer_id': customerId,
        'notes': notes,
        'archived': archived ? 1 : 0,
      };
}

/// Template for a cost that repeats (number rental, subscription). Nothing
/// is posted automatically: due templates are listed and the user records
/// each one, which pre-fills an [Expense] and moves [nextDue] forward.
class RecurringExpense {
  static const monthly = 'monthly';
  static const yearly = 'yearly';

  final String id;
  final String? vendorId;
  final String vendorName;
  final String? categoryId;
  final String entryType;
  final String description;
  final String currencyCode;
  final double amount;
  final double taxAmount;
  final String taxKind;
  final double inrAmount;
  final String? paymentMethod;
  final String? customerId;
  final String? projectId;
  final String frequency;
  final DateTime nextDue;
  final bool active;

  const RecurringExpense({
    required this.id,
    this.vendorId,
    this.vendorName = '',
    this.categoryId,
    this.entryType = Expense.typeSubscription,
    this.description = '',
    this.currencyCode = 'INR',
    required this.amount,
    this.taxAmount = 0,
    this.taxKind = 'none',
    required this.inrAmount,
    this.paymentMethod,
    this.customerId,
    this.projectId,
    this.frequency = monthly,
    required this.nextDue,
    this.active = true,
  });

  /// The date after [nextDue] for this frequency (month-end safe).
  DateTime get followingDue {
    final months = frequency == yearly ? 12 : 1;
    final target = DateTime(nextDue.year, nextDue.month + months, 1);
    final lastDay = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(target.year, target.month,
        nextDue.day > lastDay ? lastDay : nextDue.day);
  }

  factory RecurringExpense.fromMap(Map<String, dynamic> m) => RecurringExpense(
        id: m['id'] as String,
        vendorId: m['vendor_id'] as String?,
        vendorName: m['vendor_name'] as String? ?? '',
        categoryId: m['category_id'] as String?,
        entryType: m['entry_type'] as String? ?? Expense.typeSubscription,
        description: m['description'] as String? ?? '',
        currencyCode: m['currency_code'] as String? ?? 'INR',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        taxAmount: (m['tax_amount'] as num?)?.toDouble() ?? 0,
        taxKind: m['tax_kind'] as String? ?? 'none',
        inrAmount: (m['inr_amount'] as num?)?.toDouble() ?? 0,
        paymentMethod: m['payment_method'] as String?,
        customerId: m['customer_id'] as String?,
        projectId: m['project_id'] as String?,
        frequency: m['frequency'] as String? ?? monthly,
        nextDue: DateTime.parse(m['next_due'] as String),
        active: (m['active'] as num?)?.toInt() != 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'vendor_id': vendorId,
        'vendor_name': vendorName,
        'category_id': categoryId,
        'entry_type': entryType,
        'description': description,
        'currency_code': currencyCode,
        'amount': amount,
        'tax_amount': taxAmount,
        'tax_kind': taxKind,
        'inr_amount': inrAmount,
        'payment_method': paymentMethod,
        'customer_id': customerId,
        'project_id': projectId,
        'frequency': frequency,
        'next_due': nextDue.toIso8601String(),
        'active': active ? 1 : 0,
      };
}

/// A receipt/invoice file attached to an [Expense] (metadata only; the bytes
/// are fetched separately).
class ExpenseAttachment {
  final String id;
  final String expenseId;
  final String fileName;
  final String mimeType;
  final int size;
  final DateTime createdAt;

  const ExpenseAttachment({
    required this.id,
    required this.expenseId,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.createdAt,
  });

  factory ExpenseAttachment.fromMap(Map<String, dynamic> m) => ExpenseAttachment(
        id: m['id'] as String,
        expenseId: m['expense_id'] as String,
        fileName: m['file_name'] as String? ?? 'file',
        mimeType: m['mime_type'] as String? ?? 'application/octet-stream',
        size: (m['size'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'expense_id': expenseId,
        'file_name': fileName,
        'mime_type': mimeType,
        'size': size,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Filters for the expense list; all optional.
class ExpenseFilter {
  final DateTime? from;
  final DateTime? to;
  final String? vendorId;
  final String? categoryId;
  final String? entryType;
  final String? customerId;
  final String? projectId;
  final String search;

  const ExpenseFilter({
    this.from,
    this.to,
    this.vendorId,
    this.categoryId,
    this.entryType,
    this.customerId,
    this.projectId,
    this.search = '',
  });

  Map<String, dynamic> toJson() => {
        'from': from?.toIso8601String(),
        'to': to?.toIso8601String(),
        'vendorId': vendorId,
        'categoryId': categoryId,
        'entryType': entryType,
        'customerId': customerId,
        'projectId': projectId,
        'search': search,
      };

  factory ExpenseFilter.fromJson(Map<String, dynamic> j) => ExpenseFilter(
        from: j['from'] == null ? null : DateTime.parse(j['from'] as String),
        to: j['to'] == null ? null : DateTime.parse(j['to'] as String),
        vendorId: j['vendorId'] as String?,
        categoryId: j['categoryId'] as String?,
        entryType: j['entryType'] as String?,
        customerId: j['customerId'] as String?,
        projectId: j['projectId'] as String?,
        search: j['search'] as String? ?? '',
      );
}
