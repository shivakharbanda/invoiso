import 'package:invoiso_core/common/common.dart';
import 'package:invoiso_core/domain/purchase_bill_calculator.dart';
import 'package:invoiso_core/domain/purchase_bill_totals_calculator.dart';
import 'purchase_bill_item.dart';
import 'supplier_payment.dart';

class PurchaseBill {
  String id;
  String?
      supplierId; // nullable — walk-in/free-text supplier via supplierName only
  String supplierName;
  String? billNumber;
  DateTime billDate;
  String? notes;
  String? attachmentPath; // reserved for future OCR, no UI yet
  List<PurchaseBillItem> items;
  List<SupplierPayment> payments;
  DateTime? createdAt;
  bool isDraft; // draft = no stock/ledger/purchase-price effect, no payments

  PurchaseBill({
    required this.id,
    this.supplierId,
    this.supplierName = '',
    this.billNumber,
    required this.billDate,
    this.notes,
    this.attachmentPath,
    required this.items,
    this.payments = const [],
    this.createdAt,
    this.isDraft = false,
  });

  PurchaseBillTotals get _totals => PurchaseBillTotalsCalculator.totals(
        lines: items.map((item) => PurchaseBillTotalsCalculator.line(
              costPerUnit: item.costPerUnit,
              quantity: item.quantity,
              taxRatePercent: item.taxRate,
              costIncludesTax: item.costIncludesTax,
            )),
      );

  double get subtotal => _totals.subtotal;

  double get tax => _totals.tax;

  double get total => _totals.total;

  double get amountPaid => payments.fold(0.0, (sum, p) => sum + p.amountPaid);

  double get outstandingBalance =>
      PurchaseBillCalculator.outstanding(total: total, paid: amountPaid);

  PaymentStatus get paymentStatus =>
      PurchaseBillCalculator.paymentStatus(total: total, paid: amountPaid);

  Map<String, dynamic> toJson() => {
        'id': id,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'billNumber': billNumber,
        'billDate': billDate.toIso8601String(),
        'notes': notes,
        'attachmentPath': attachmentPath,
        'items': items.map((i) => i.toMap()).toList(),
        'payments': payments.map((p) => p.toMap()).toList(),
        'createdAt': createdAt?.toIso8601String(),
        'isDraft': isDraft,
      };

  factory PurchaseBill.fromJson(Map<String, dynamic> j) => PurchaseBill(
        id: j['id'] as String,
        supplierId: j['supplierId'] as String?,
        supplierName: j['supplierName'] as String,
        billNumber: j['billNumber'] as String?,
        billDate: DateTime.parse(j['billDate'] as String),
        notes: j['notes'] as String?,
        attachmentPath: j['attachmentPath'] as String?,
        items: [
          for (final e in j['items'] as List)
            PurchaseBillItem.fromMap((e as Map).cast<String, dynamic>())
        ],
        payments: [
          for (final e in j['payments'] as List)
            SupplierPayment.fromMap((e as Map).cast<String, dynamic>())
        ],
        createdAt: j['createdAt'] == null
            ? null
            : DateTime.parse(j['createdAt'] as String),
        isDraft: j['isDraft'] as bool,
      );
}
