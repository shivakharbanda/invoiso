/// Invoice list filters applied in the query, before pagination
/// (Issues.md #39). Defaults = no filtering.
class InvoiceListFilter {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final int? numberFrom;
  final int? numberTo;

  /// 'all' | 'overdue' | 'due_today' | 'due_week' | 'due_month'
  final String dueDate;

  /// 'all' | 'paid' | 'partial' | 'unpaid' | 'declined' — applies to
  /// 'Invoice' rows only. 'declined' = only declined invoices.
  final String paymentStatus;

  /// Drop fully-paid Invoices (other types are kept).
  final bool hidePaid;

  /// Drop declined invoices. Ignored when [paymentStatus] is 'declined'.
  final bool hideDeclined;

  const InvoiceListFilter({
    this.dateFrom,
    this.dateTo,
    this.numberFrom,
    this.numberTo,
    this.dueDate = 'all',
    this.paymentStatus = 'all',
    this.hidePaid = false,
    this.hideDeclined = false,
  });

  /// True when a filter depends on each invoice's total/paid balance, which
  /// isn't stored — those are resolved in Dart over the SQL-filtered set.
  bool get needsBalance =>
      hidePaid ||
      dueDate == 'overdue' ||
      (paymentStatus != 'all' && paymentStatus != 'declined');

  Map<String, dynamic> toJson() => {
        'dateFrom': dateFrom?.toIso8601String(),
        'dateTo': dateTo?.toIso8601String(),
        'numberFrom': numberFrom,
        'numberTo': numberTo,
        'dueDate': dueDate,
        'paymentStatus': paymentStatus,
        'hidePaid': hidePaid,
        'hideDeclined': hideDeclined,
      };

  factory InvoiceListFilter.fromJson(Map<String, dynamic> j) =>
      InvoiceListFilter(
        dateFrom: j['dateFrom'] == null
            ? null
            : DateTime.parse(j['dateFrom'] as String),
        dateTo:
            j['dateTo'] == null ? null : DateTime.parse(j['dateTo'] as String),
        numberFrom: (j['numberFrom'] as num?)?.toInt(),
        numberTo: (j['numberTo'] as num?)?.toInt(),
        dueDate: j['dueDate'] as String,
        paymentStatus: j['paymentStatus'] as String,
        hidePaid: j['hidePaid'] as bool,
        hideDeclined: j['hideDeclined'] as bool,
      );
}
