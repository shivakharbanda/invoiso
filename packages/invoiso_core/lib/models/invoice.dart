import 'package:invoiso_core/common/common.dart';
import 'package:invoiso_core/domain/invoice_calculator.dart';
import 'package:invoiso_core/domain/invoice_totals_calculator.dart';
import 'additional_cost.dart';
import 'custom_field_value.dart';
import 'customer.dart';
import 'invoice_item.dart';
import 'invoice_payment.dart';

class Invoice {
  String id;
  String?
      invoiceNumber; // per-type sequential display number; null on legacy rows (falls back to id)
  Customer customer;
  List<InvoiceItem> items;
  DateTime date;
  String? notes;
  double taxRate;
  String type;
  String?
      invoiceTitle; // GST document title override (e.g. "Tax Invoice", "Bill of Supply"); null = use type
  String currencyCode;
  String currencySymbol;
  TaxMode taxMode;
  bool
      isInterState; // India: interstate supply → show IGST instead of CGST/SGST
  List<InvoicePayment> payments;
  String? upiId; // selected UPI account for this invoice
  String? bankAccountId; // selected bank account label key for this invoice
  DateTime? dueDate;
  String?
      quantityLabel; // custom label for the Qty column (e.g. "Words", "Hours")
  List<AdditionalCost>
      additionalCosts; // e.g. Shipping, Packaging (zero tax, added after tax)
  double previousBalance;
  InvoiceDiscountType
      invoiceDiscountType; // invoice-level discount, applied after tax
  double invoiceDiscountValue;
  bool hideInvoiceNumber; // hide real invoice number in PDF output only
  String?
      customInvoiceNumber; // shown instead of invoiceNumber in PDF when hideInvoiceNumber is true
  List<CustomFieldValue>
      customFields; // user-defined per-invoice fields (e.g. Vehicle No, Delivery Note)
  String?
      status; // quotation lifecycle: 'draft'|'sent'|'accepted'|'declined'|'converted'; null == 'draft'.
  // For type=='Invoice': only 'declined' is used (invoice voided, stock returned); null == active.
  String?
      convertedToInvoiceId; // on a quotation → id of the invoice it was converted into
  String?
      convertedFromInvoiceId; // on an invoice → id of the source quotation it was converted from

  Invoice({
    required this.id,
    this.invoiceNumber,
    required this.customer,
    required this.items,
    required this.date,
    required this.type,
    this.invoiceTitle,
    this.notes,
    this.taxRate = 0.0,
    this.currencyCode = 'INR',
    this.currencySymbol = '₹',
    this.taxMode = TaxMode.global,
    this.isInterState = false,
    this.payments = const [],
    this.upiId,
    this.bankAccountId,
    this.dueDate,
    this.quantityLabel,
    this.additionalCosts = const [],
    this.previousBalance = 0.0,
    this.invoiceDiscountType = InvoiceDiscountType.percent,
    this.invoiceDiscountValue = 0.0,
    this.hideInvoiceNumber = false,
    this.customInvoiceNumber,
    this.customFields = const [],
    this.status,
    this.convertedToInvoiceId,
    this.convertedFromInvoiceId,
  });

  bool get isConverted => status == 'converted';

  /// Text to render for the invoice number in PDF/receipt output, or null to omit the line entirely.
  String? pdfNumberText(String invoicePrefix, {bool showLeadingZeros = true}) {
    if (hideInvoiceNumber) {
      final c = customInvoiceNumber?.trim();
      return (c != null && c.isNotEmpty) ? c : null;
    }
    final number = invoiceNumber ?? id;
    if (showLeadingZeros) return '$invoicePrefix$number';
    final stripped = number.replaceFirst(RegExp(r'^0+'), '');
    return '$invoicePrefix${stripped.isEmpty ? '0' : stripped}';
  }

  InvoiceTotals get _totals => InvoiceTotalsCalculator.totals(
        lines: items.map((item) => item._amountsForInvoice(
            taxMode: taxMode, globalTaxRatePercent: taxRate * 100)),
        taxMode: taxMode,
        globalTaxRate: taxRate,
        globalTaxRateFormat: TaxRateFormat.fraction,
        additionalCostsTotal: additionalCostsTotal,
        invoiceDiscountType: invoiceDiscountType,
        invoiceDiscountValue: invoiceDiscountValue,
      );

  double get subtotal => _totals.subtotal;

  double get grossSubtotal => _totals.grossSubtotal;

  double get totalDiscount => _totals.totalDiscount;

  double get tax => _totals.tax;

  double get additionalCostsTotal =>
      additionalCosts.fold(0.0, (sum, c) => sum + c.amount);

  double get invoiceDiscountAmount => _totals.invoiceDiscountAmount;

  double get total => _totals.total;

  double get amountPaid => payments.fold(0.0, (sum, p) => sum + p.amountPaid);

  double get outstandingBalance =>
      InvoiceCalculator.outstanding(total: total, paid: amountPaid);

  PaymentStatus get paymentStatus =>
      InvoiceCalculator.paymentStatus(total: total, paid: amountPaid);

  Map<String, dynamic> toJson() => {
        'id': id,
        'invoiceNumber': invoiceNumber,
        'customer': customer.toMap(),
        'items': items.map((i) => i.toJson()).toList(),
        'date': date.toIso8601String(),
        'notes': notes,
        'taxRate': taxRate,
        'type': type,
        'invoiceTitle': invoiceTitle,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'taxMode': taxMode.name,
        'isInterState': isInterState,
        'payments': payments.map((p) => p.toMap()).toList(),
        'upiId': upiId,
        'bankAccountId': bankAccountId,
        'dueDate': dueDate?.toIso8601String(),
        'quantityLabel': quantityLabel,
        'additionalCosts': additionalCosts.map((c) => c.toJson()).toList(),
        'previousBalance': previousBalance,
        'invoiceDiscountType': invoiceDiscountType.name,
        'invoiceDiscountValue': invoiceDiscountValue,
        'hideInvoiceNumber': hideInvoiceNumber,
        'customInvoiceNumber': customInvoiceNumber,
        'customFields': customFields.map((f) => f.toJson()).toList(),
        'status': status,
        'convertedToInvoiceId': convertedToInvoiceId,
        'convertedFromInvoiceId': convertedFromInvoiceId,
      };

  factory Invoice.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(String key) =>
        [for (final e in j[key] as List) (e as Map).cast<String, dynamic>()];
    return Invoice(
      id: j['id'] as String,
      invoiceNumber: j['invoiceNumber'] as String?,
      customer:
          Customer.fromMap((j['customer'] as Map).cast<String, dynamic>()),
      items: maps('items').map(InvoiceItem.fromJson).toList(),
      date: DateTime.parse(j['date'] as String),
      notes: j['notes'] as String?,
      taxRate: (j['taxRate'] as num).toDouble(),
      type: j['type'] as String,
      invoiceTitle: j['invoiceTitle'] as String?,
      currencyCode: j['currencyCode'] as String,
      currencySymbol: j['currencySymbol'] as String,
      taxMode: TaxMode.values.byName(j['taxMode'] as String),
      isInterState: j['isInterState'] as bool,
      payments: maps('payments').map(InvoicePayment.fromMap).toList(),
      upiId: j['upiId'] as String?,
      bankAccountId: j['bankAccountId'] as String?,
      dueDate:
          j['dueDate'] == null ? null : DateTime.parse(j['dueDate'] as String),
      quantityLabel: j['quantityLabel'] as String?,
      additionalCosts:
          maps('additionalCosts').map(AdditionalCost.fromJson).toList(),
      previousBalance: (j['previousBalance'] as num).toDouble(),
      invoiceDiscountType:
          InvoiceDiscountType.values.byName(j['invoiceDiscountType'] as String),
      invoiceDiscountValue: (j['invoiceDiscountValue'] as num).toDouble(),
      hideInvoiceNumber: j['hideInvoiceNumber'] as bool,
      customInvoiceNumber: j['customInvoiceNumber'] as String?,
      customFields:
          maps('customFields').map(CustomFieldValue.fromJson).toList(),
      status: j['status'] as String?,
      convertedToInvoiceId: j['convertedToInvoiceId'] as String?,
      convertedFromInvoiceId: j['convertedFromInvoiceId'] as String?,
    );
  }
}

extension _InvoiceItemTotals on InvoiceItem {
  InvoiceLineAmount _amountsForInvoice({
    required TaxMode taxMode,
    required double globalTaxRatePercent,
  }) =>
      InvoiceTotalsCalculator.line(
        price: effectivePrice,
        quantity: quantity,
        discount: discount,
        discountPerUnit: discountPerUnit,
        discountIsPercent: discountIsPercent,
        extraCost: extraCost ?? 0.0,
        taxRatePercent: product.tax_rate.toDouble(),
        priceIncludesTax: product.priceIncludesTax,
        taxMode: taxMode,
        globalTaxRatePercent: globalTaxRatePercent,
      );
}
