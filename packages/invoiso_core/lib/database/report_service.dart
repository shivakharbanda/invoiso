import 'package:invoiso_core/database/database_helper.dart';
import 'package:invoiso_core/common/common.dart';
import 'package:invoiso_core/domain/customer_identity.dart';
import 'package:invoiso_core/domain/invoice_calculator.dart';
import 'package:invoiso_core/domain/invoice_totals_calculator.dart';
import 'package:invoiso_core/models/additional_cost.dart';
import 'package:invoiso_core/models/cash_ledger_entry.dart';
import 'package:invoiso_core/utils/app_date.dart';
import 'package:invoiso_core/models/report_models.dart';
export 'package:invoiso_core/models/report_models.dart';

// ─── Internal row ─────────────────────────────────────────────────────────────

class _InvRow {
  final String id;
  final String customerKey;
  final String customerName;
  final String date;
  final String? dueDate;
  final double total;
  final double paid;
  final double outstanding;
  // Tax-exclusive product revenue after the invoice-level discount (its
  // net-subtotal share), and cost of goods sold — for profit reporting.
  final double netRevenue;
  final double cogs;
  final String currencyCode;
  final String currencySymbol;

  const _InvRow({
    required this.id,
    required this.customerKey,
    required this.customerName,
    required this.date,
    this.dueDate,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.netRevenue,
    required this.cogs,
    required this.currencyCode,
    required this.currencySymbol,
  });
}

class _StatementLineDraft {
  final String date;
  final int order;
  final String type;
  final String reference;
  final String description;
  final double debit;
  final double credit;

  const _StatementLineDraft({
    required this.date,
    required this.order,
    required this.type,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
  });
}

// ─── Service ───────────────────────────────────────────────────────────────────

class ReportService {
  static final _db = DatabaseHelper();
  static const _invoiceItemNetSql = 'CASE WHEN ii.discount_is_percent = 1 '
      'THEN COALESCE(ii.unit_price, ii.product_price) * ii.quantity '
      '* (1 - ii.discount / 100.0) + COALESCE(ii.extra_cost, 0) '
      'WHEN ii.discount_per_unit = 1 '
      'THEN (COALESCE(ii.unit_price, ii.product_price) - ii.discount) * ii.quantity '
      '+ COALESCE(ii.extra_cost, 0) '
      'ELSE COALESCE(ii.unit_price, ii.product_price) * ii.quantity '
      '- ii.discount + COALESCE(ii.extra_cost, 0) END';
  static const _invoiceItemDiscountSql = 'CASE WHEN ii.discount_is_percent = 1 '
      'THEN COALESCE(ii.unit_price, ii.product_price) * ii.quantity * ii.discount / 100.0 '
      'WHEN ii.discount_per_unit = 1 '
      'THEN ii.discount * ii.quantity ELSE ii.discount END';
  // Revenue basis for P&L/dashboard: backs out embedded tax for
  // tax-inclusive-priced items so "revenue" stays a tax-exclusive figure,
  // matching the sales tax report and invoice subtotal. Only applies in
  // per-item tax mode — global-mode invoices never derive tax from
  // per-product rates, so the stored product tax rate isn't part of that
  // invoice's actual tax calc.
  static const _invoiceItemTaxableNetSql =
      "CASE WHEN i.tax_mode = 'per_item' AND ii.product_price_includes_tax = 1 "
      'AND ii.product_tax_rate > 0 '
      'THEN ($_invoiceItemNetSql) / (1 + ii.product_tax_rate / 100.0) '
      'ELSE $_invoiceItemNetSql END';

  // ── Batch loader: invoice totals computed in Dart (accurate, no N+1) ────────

  static Future<List<_InvRow>> _loadRows({
    String type = 'Invoice',
    DateTime? from,
    DateTime? to,
    String? currencyCode,
    String? customerKey,
  }) async {
    final db = await _db.database;

    final sb = StringBuffer(
        "type = ? AND deleted_at IS NULL AND (status IS NULL OR status != 'declined')");
    final args = <dynamic>[type];
    if (from != null) {
      sb.write(' AND date >= ?');
      args.add(AppDate.dateKeyStart(from));
    }
    if (to != null) {
      sb.write(' AND date <= ?');
      args.add(AppDate.dateKeyEnd(to));
    }
    if (currencyCode != null) {
      sb.write(' AND (currency_code = ? OR currency_code IS NULL)');
      args.add(currencyCode);
    }
    if (customerKey != null) {
      sb.write(" AND COALESCE(NULLIF(customer_id, ''), customer_name) = ?");
      args.add(customerKey);
    }

    final invRows = await db.query(
      'invoices',
      columns: [
        'id',
        'customer_id',
        'customer_name',
        'date',
        'due_date',
        'tax_rate',
        'tax_mode',
        'additional_costs',
        'invoice_discount_type',
        'invoice_discount_value',
        'currency_code',
        'currency_symbol',
      ],
      where: sb.toString(),
      whereArgs: args,
    );
    if (invRows.isEmpty) return [];

    // Subquery instead of one `?` per id — see Issues.md #36.
    final invSubquery = '(SELECT id FROM invoices WHERE $sb)';

    final itemRows = await db.rawQuery(
      'SELECT invoice_id, quantity, unit_price, product_price, discount, '
      'discount_per_unit, discount_is_percent, extra_cost, product_tax_rate, product_price_includes_tax, '
      'product_purchase_price '
      'FROM invoice_items WHERE invoice_id IN $invSubquery',
      args,
    );

    final payRows = await db.rawQuery(
      'SELECT invoice_id, COALESCE(SUM(amount_paid), 0.0) AS paid '
      'FROM invoice_payments WHERE invoice_id IN $invSubquery '
      'GROUP BY invoice_id',
      args,
    );

    final itemsByInv = <String, List<Map<String, dynamic>>>{};
    for (final r in itemRows) {
      (itemsByInv[r['invoice_id'] as String] ??= [])
          .add(r as Map<String, dynamic>);
    }

    final paidByInv = <String, double>{
      for (final r in payRows)
        r['invoice_id'] as String: (r['paid'] as num).toDouble()
    };

    return invRows.map((inv) {
      final id = inv['id'] as String;
      final taxMode = TaxModeExtension.fromKey(inv['tax_mode'] as String?);
      final taxRate = (inv['tax_rate'] as num?)?.toDouble() ?? 0.0;
      final items = itemsByInv[id] ?? [];
      final paid = paidByInv[id] ?? 0.0;

      final addCosts =
          AdditionalCost.listFromJson(inv['additional_costs'] as String?)
              .fold(0.0, (s, c) => s + c.amount);
      final totals = InvoiceTotalsCalculator.totals(
        lines: items.map((r) => InvoiceTotalsCalculator.lineFromDbRow(r,
            taxMode: taxMode, globalTaxRatePercent: taxRate * 100)),
        taxMode: taxMode,
        globalTaxRate: taxRate,
        globalTaxRateFormat: TaxRateFormat.fraction,
        additionalCostsTotal: addCosts,
        invoiceDiscountType: InvoiceDiscountTypeExtension.fromKey(
            inv['invoice_discount_type'] as String?),
        invoiceDiscountValue:
            (inv['invoice_discount_value'] as num?)?.toDouble() ?? 0.0,
      );
      final total = totals.total;
      final outstanding =
          InvoiceCalculator.outstanding(total: total, paid: paid);

      // Invoice-level discount applies to the whole pre-discount total; give
      // the tax-exclusive product-revenue portion its proportional share so
      // profit stays consistent with `billed`.
      final netRevenue = totals.preDiscountTotal <= 0
          ? totals.subtotal
          : totals.subtotal -
              totals.invoiceDiscountAmount *
                  (totals.subtotal / totals.preDiscountTotal);
      final cogs = items.fold<double>(
          0.0,
          (s, r) =>
              s +
              (((r['quantity'] as num?)?.toDouble() ?? 0.0) *
                  ((r['product_purchase_price'] as num?)?.toDouble() ?? 0.0)));

      return _InvRow(
        id: id,
        customerKey: CustomerIdentity.key(
          id: inv['customer_id'] as String?,
          name: inv['customer_name'] as String?,
        ),
        customerName:
            CustomerIdentity.displayName(inv['customer_name'] as String?),
        date: inv['date'] as String? ?? '',
        dueDate: inv['due_date'] as String?,
        total: total,
        paid: paid,
        outstanding: outstanding,
        netRevenue: netRevenue,
        cogs: cogs,
        currencyCode: inv['currency_code'] as String? ?? 'INR',
        currencySymbol: inv['currency_symbol'] as String? ?? 'Rs.',
      );
    }).toList();
  }

  // ── 1. Revenue KPIs ────────────────────────────────────────────────────────

  /// Tax-exclusive revenue and COGS per customer (keyed like customer
  /// statements: customer id, or name for walk-ins) — the revenue side of
  /// client profitability in the spend reports.
  static Future<Map<String, ({String name, double revenue, double cogs})>>
      getRevenueByCustomer(DateTime from, DateTime to,
          {String? currencyCode}) async {
    final rows =
        await _loadRows(from: from, to: to, currencyCode: currencyCode);
    final out = <String, ({String name, double revenue, double cogs})>{};
    for (final r in rows) {
      final prev = out[r.customerKey];
      out[r.customerKey] = (
        name: r.customerName,
        revenue: (prev?.revenue ?? 0) + r.netRevenue,
        cogs: (prev?.cogs ?? 0) + r.cogs,
      );
    }
    return out;
  }

  static Future<RevenueKpi> getRevenueSummary(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadRows(from: from, to: to, currencyCode: currencyCode);
    if (rows.isEmpty) return RevenueKpi.empty;

    double billed = 0,
        collected = 0,
        outstanding = 0,
        profit = 0,
        realizedProfit = 0;
    for (final r in rows) {
      billed += r.total;
      collected += r.paid;
      outstanding += r.outstanding;
      final margin = r.netRevenue - r.cogs;
      profit += margin;
      final collectedRatio =
          r.total > 0 ? (r.paid / r.total).clamp(0.0, 1.0) : 0.0;
      realizedProfit += margin * collectedRatio;
    }
    return RevenueKpi(
      invoiceCount: rows.length,
      billed: billed,
      collected: collected,
      outstanding: outstanding,
      avgInvoiceValue: billed / rows.length,
      profit: profit,
      realizedProfit: realizedProfit,
    );
  }

  /// Count of sold line items in [from]..[to] with no purchase-price
  /// snapshot (0 or null) — i.e. sales made before purchase price was set on
  /// the product, or before this feature existed. Profit/margin figures are
  /// understated by this many items' worth of unknown cost.
  static Future<int> getMissingCostItemCount(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final db = await _db.database;
    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final ccFilter = currencyCode != null
        ? 'AND (i.currency_code = ? OR i.currency_code IS NULL) '
        : '';
    final args = <Object?>[
      if (currencyCode != null) currencyCode,
      f,
      t,
    ];
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS cnt "
      "FROM invoice_items ii "
      "JOIN invoices i ON i.id = ii.invoice_id "
      "WHERE i.deleted_at IS NULL AND i.type = 'Invoice' "
      "AND (i.status IS NULL OR i.status != 'declined') "
      "AND (ii.product_purchase_price IS NULL OR ii.product_purchase_price = 0) "
      "$ccFilter"
      "AND i.date >= ? AND i.date <= ?",
      args,
    );
    return (rows.first['cnt'] as num?)?.toInt() ?? 0;
  }

  // ── 2. Monthly revenue trend ───────────────────────────────────────────────

  static Future<List<MonthlyPoint>> getMonthlyRevenueTrend(
      DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadRows(from: from, to: to, currencyCode: currencyCode);
    final db = await _db.database;

    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final currencyFilter = currencyCode != null
        ? 'AND (i.currency_code = ? OR i.currency_code IS NULL) '
        : '';
    final args = <Object?>[
      if (currencyCode != null) currencyCode,
      f,
      t,
    ];

    // Collected grouped by payment date (more accurate for cash-flow view)
    final collectedRows = await db.rawQuery(
      "SELECT strftime('%Y-%m', ip.date_paid) AS month, "
      "COALESCE(SUM(ip.amount_paid), 0.0) AS collected "
      "FROM invoice_payments ip "
      "JOIN invoices i ON ip.invoice_id = i.id "
      "WHERE i.deleted_at IS NULL AND i.type = 'Invoice' "
      "AND (i.status IS NULL OR i.status != 'declined') "
      "$currencyFilter"
      "AND ip.date_paid >= ? AND ip.date_paid <= ? "
      "GROUP BY month ORDER BY month",
      args,
    );

    final collectedByMonth = <String, double>{
      for (final r in collectedRows)
        r['month'] as String: (r['collected'] as num).toDouble()
    };

    // Billed / net sales / COGS / outstanding / count grouped by invoice date
    final billedByMonth = <String, double>{};
    final netByMonth = <String, double>{};
    final cogsByMonth = <String, double>{};
    final outstandingByMonth = <String, double>{};
    final countByMonth = <String, int>{};
    for (final r in rows) {
      if (r.date.length < 7) continue;
      final m = r.date.substring(0, 7);
      billedByMonth[m] = (billedByMonth[m] ?? 0) + r.total;
      netByMonth[m] = (netByMonth[m] ?? 0) + r.netRevenue;
      cogsByMonth[m] = (cogsByMonth[m] ?? 0) + r.cogs;
      outstandingByMonth[m] = (outstandingByMonth[m] ?? 0) + r.outstanding;
      countByMonth[m] = (countByMonth[m] ?? 0) + 1;
    }

    final allMonths = {...billedByMonth.keys, ...collectedByMonth.keys}.toList()
      ..sort();

    return allMonths
        .map((m) => MonthlyPoint(
              month: m,
              billed: billedByMonth[m] ?? 0,
              collected: collectedByMonth[m] ?? 0,
              profit: (netByMonth[m] ?? 0) - (cogsByMonth[m] ?? 0),
              invoiceCount: countByMonth[m] ?? 0,
              netSales: netByMonth[m] ?? 0,
              cogs: cogsByMonth[m] ?? 0,
              outstanding: outstandingByMonth[m] ?? 0,
            ))
        .toList();
  }

  // ── 2b. Daily sales/profit trend ────────────────────────────────────────────

  static Future<List<DailyPoint>> getDailyRevenueTrend(
      DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadRows(from: from, to: to, currencyCode: currencyCode);

    // Sales = tax-exclusive product revenue after invoice discount; profit
    // subtracts COGS. Both keep the same basis as the Revenue-tab profit KPI.
    final countByDay = <String, int>{};
    final netByDay = <String, double>{};
    final cogsByDay = <String, double>{};
    for (final r in rows) {
      if (r.date.length < 10) continue;
      final d = r.date.substring(0, 10);
      countByDay[d] = (countByDay[d] ?? 0) + 1;
      netByDay[d] = (netByDay[d] ?? 0) + r.netRevenue;
      cogsByDay[d] = (cogsByDay[d] ?? 0) + r.cogs;
    }

    final days = countByDay.keys.toList()..sort();
    return days
        .map((d) => DailyPoint(
              date: d,
              invoiceCount: countByDay[d]!,
              billed: netByDay[d] ?? 0.0,
              cogs: cogsByDay[d] ?? 0.0,
            ))
        .toList();
  }

  /// Adds each day's net Cash / UPI-Bank change to [rows]. Days with only
  /// ledger activity get a row with no invoices; the result stays date-sorted.
  static List<DailyPoint> mergeDailyCashUpi(
      List<DailyPoint> rows, Map<String, CashDailyNet> net) {
    final byDate = {for (final d in rows) d.date: d};
    final days = {...byDate.keys, ...net.keys}.toList()..sort();
    return days.map((day) {
      final d = byDate[day];
      final n = net[day];
      return DailyPoint(
        date: day,
        invoiceCount: d?.invoiceCount ?? 0,
        billed: d?.billed ?? 0,
        cogs: d?.cogs ?? 0,
        cash: n?.cash ?? 0,
        upiBank: n?.upiBank ?? 0,
        paidCash: n?.payCash ?? 0,
        paidUpi: n?.payUpi ?? 0,
        serviceIncome: n?.fee ?? 0,
        exchangeCount: n?.exchanges ?? 0,
      );
    }).toList();
  }

  /// Daily Report table lines: per day, an invoice line and/or a cash-exchange
  /// line, each only when the day has that activity and its type is wanted.
  static List<DailyLine> dailyLines(List<DailyPoint> rows,
          {bool invoices = true, bool exchanges = false}) =>
      [
        for (final d in rows) ...[
          if (invoices && d.hasInvoiceActivity) (d: d, exchange: false),
          if (exchanges && d.hasExchangeActivity) (d: d, exchange: true),
        ],
      ];

  // ── 3. Payment status breakdown ────────────────────────────────────────────

  static Future<StatusBreakdown> getPaymentStatusBreakdown(
      DateTime from, DateTime to,
      {String? currencyCode}) async {
    final rows =
        await _loadRows(from: from, to: to, currencyCode: currencyCode);
    int paid = 0, partial = 0, unpaid = 0;
    for (final r in rows) {
      switch (InvoiceCalculator.paymentStatus(total: r.total, paid: r.paid)) {
        case PaymentStatus.unpaid:
          unpaid++;
        case PaymentStatus.paid:
          paid++;
        case PaymentStatus.partial:
          partial++;
      }
    }
    return StatusBreakdown(paid: paid, partial: partial, unpaid: unpaid);
  }

  // ── 4. Aged receivables (all time, all overdue) ────────────────────────────

  static Future<List<AgedReceivable>> getAgedReceivables(
      {String? currencyCode}) async {
    final rows = await _loadRows(currencyCode: currencyCode);
    final now = DateTime.now();
    final result = <AgedReceivable>[];

    for (final r in rows) {
      if (r.outstanding <= InvoiceCalculator.moneyEpsilon) continue;
      final dueDate = r.dueDate != null ? DateTime.tryParse(r.dueDate!) : null;
      final bool noDueDate = dueDate == null;
      final daysOverdue =
          InvoiceCalculator.daysOverdue(dueDate: dueDate, asOf: now);
      result.add(AgedReceivable(
        invoiceId: r.id,
        customerName: r.customerName,
        outstanding: r.outstanding,
        daysOverdue: daysOverdue,
        hasNoDueDate: noDueDate,
      ));
    }
    // Sort: no-due-date last, then by days overdue descending
    result.sort((a, b) {
      if (a.hasNoDueDate != b.hasNoDueDate) return a.hasNoDueDate ? 1 : -1;
      return b.daysOverdue.compareTo(a.daysOverdue);
    });
    return result;
  }

  /// A/R Aging Summary: outstanding balance per customer split into aging
  /// buckets (all-time, as of today). Bucket boundaries match
  /// [getAgedReceivables]. Sorted by total outstanding descending.
  static Future<List<AgedReceivableSummaryRow>> getAgedReceivableSummary(
      {String? currencyCode}) async {
    final rows = await _loadRows(currencyCode: currencyCode);
    final now = DateTime.now();
    // Per customer: [current, 0-30, 31-60, 61-90, 90+, noDueDate]
    final buckets = <String, List<double>>{};
    final names = <String, String>{};

    for (final r in rows) {
      if (r.outstanding <= InvoiceCalculator.moneyEpsilon) continue;
      final dueDate = r.dueDate != null ? DateTime.tryParse(r.dueDate!) : null;
      final b =
          buckets.putIfAbsent(r.customerKey, () => <double>[0, 0, 0, 0, 0, 0]);
      names[r.customerKey] = r.customerName;
      if (dueDate == null) {
        b[5] += r.outstanding;
        continue;
      }
      final d = InvoiceCalculator.daysOverdue(dueDate: dueDate, asOf: now);
      final idx = d == 0
          ? 0
          : d <= 30
              ? 1
              : d <= 60
                  ? 2
                  : d <= 90
                      ? 3
                      : 4;
      b[idx] += r.outstanding;
    }

    final result = buckets.entries
        .map((e) => AgedReceivableSummaryRow(
              customerName: names[e.key] ?? e.key,
              current: e.value[0],
              d0to30: e.value[1],
              d31to60: e.value[2],
              d61to90: e.value[3],
              d90plus: e.value[4],
              noDueDate: e.value[5],
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  /// Total outstanding (all-time, not date-bound) per customer, keyed by
  /// customer_id — for a customer-list "Outstanding" column/filter/sort.
  static Future<Map<String, double>> getOutstandingByCustomer(
      {String? currencyCode}) async {
    final rows = await _loadRows(currencyCode: currencyCode);
    final result = <String, double>{};
    for (final r in rows) {
      if (r.outstanding <= InvoiceCalculator.moneyEpsilon) continue;
      result[r.customerKey] = (result[r.customerKey] ?? 0) + r.outstanding;
    }
    return result;
  }

  /// Distinct currency codes actually used across (non-deleted) invoices —
  /// for a currency picker, e.g. next to the Outstanding column.
  static Future<List<String>> getInvoiceCurrencies() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT currency_code FROM invoices "
      "WHERE deleted_at IS NULL AND type = 'Invoice' AND currency_code IS NOT NULL",
    );
    final codes = rows.map((r) => r['currency_code'] as String).toList();
    codes.sort();
    return codes;
  }

  // ── 5. Tax collected by rate ───────────────────────────────────────────────

  static Future<List<TaxBucket>> getTaxByRate(DateTime from, DateTime to,
      {String? currencyCode}) async {
    final db = await _db.database;
    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final ccFilter = currencyCode != null
        ? 'AND (i.currency_code = ? OR i.currency_code IS NULL) '
        : '';
    final dateArgs = <Object?>[
      if (currencyCode != null) currencyCode,
      f,
      t,
    ];

    final taxByRate = <double, double>{};
    final taxableByRate = <double, double>{};

    // Per-item mode: tax computed per line item's product_tax_rate
    final perItemRows = await db.rawQuery(
      "SELECT ii.product_tax_rate AS rate, "
      "SUM(CASE WHEN ii.product_price_includes_tax = 1 "
      "THEN $_invoiceItemNetSql * ii.product_tax_rate / (100 + ii.product_tax_rate) "
      "ELSE $_invoiceItemNetSql * ii.product_tax_rate / 100 "
      "END) AS tax_amount, "
      "SUM(CASE WHEN ii.product_price_includes_tax = 1 "
      "THEN $_invoiceItemNetSql * 100.0 / (100 + ii.product_tax_rate) "
      "ELSE $_invoiceItemNetSql END) AS taxable_amount "
      "FROM invoice_items ii "
      "JOIN invoices i ON i.id = ii.invoice_id "
      "WHERE i.deleted_at IS NULL AND i.type = 'Invoice' "
      "AND (i.status IS NULL OR i.status != 'declined') "
      "AND i.tax_mode = 'per_item' "
      "$ccFilter"
      "AND i.date >= ? AND i.date <= ? "
      "AND ii.product_tax_rate > 0 "
      "GROUP BY ii.product_tax_rate",
      dateArgs,
    );
    for (final r in perItemRows) {
      final rate = (r['rate'] as num).toDouble();
      taxByRate[rate] =
          (taxByRate[rate] ?? 0) + ((r['tax_amount'] as num?)?.toDouble() ?? 0);
      taxableByRate[rate] = (taxableByRate[rate] ?? 0) +
          ((r['taxable_amount'] as num?)?.toDouble() ?? 0);
    }

    // Global mode: single tax rate applied to the invoice subtotal
    final globalInvRows = await db.rawQuery(
      "SELECT i.id, i.tax_rate, i.additional_costs "
      "FROM invoices i "
      "WHERE i.deleted_at IS NULL AND i.type = 'Invoice' "
      "AND (i.status IS NULL OR i.status != 'declined') "
      "AND i.tax_mode = 'global' AND i.tax_rate > 0 "
      "$ccFilter"
      "AND i.date >= ? AND i.date <= ?",
      dateArgs,
    );

    if (globalInvRows.isNotEmpty) {
      // Subquery instead of one `?` per id — see Issues.md #36.
      final itemRows = await db.rawQuery(
        "SELECT invoice_id, quantity, unit_price, product_price, discount, "
        "discount_per_unit, discount_is_percent, extra_cost, product_tax_rate, product_price_includes_tax "
        "FROM invoice_items WHERE invoice_id IN ("
        "SELECT i.id FROM invoices i "
        "WHERE i.deleted_at IS NULL AND i.type = 'Invoice' "
        "AND i.tax_mode = 'global' AND i.tax_rate > 0 "
        "$ccFilter"
        "AND i.date >= ? AND i.date <= ?)",
        dateArgs,
      );
      final itemsByInv = <String, List<Map<String, dynamic>>>{};
      for (final r in itemRows) {
        (itemsByInv[r['invoice_id'] as String] ??= [])
            .add(r as Map<String, dynamic>);
      }
      for (final inv in globalInvRows) {
        final id = inv['id'] as String;
        final taxRate = (inv['tax_rate'] as num?)?.toDouble() ?? 0.0;
        final totals = InvoiceTotalsCalculator.totals(
          lines: (itemsByInv[id] ?? []).map((r) =>
              InvoiceTotalsCalculator.lineFromDbRow(r,
                  taxMode: TaxMode.global,
                  globalTaxRatePercent: taxRate * 100)),
          taxMode: TaxMode.global,
          globalTaxRate: taxRate,
          globalTaxRateFormat: TaxRateFormat.fraction,
        );
        final tax = totals.tax;
        final ratePercent = taxRate * 100;
        if (tax > 0) {
          taxByRate[ratePercent] = (taxByRate[ratePercent] ?? 0) + tax;
          taxableByRate[ratePercent] =
              (taxableByRate[ratePercent] ?? 0) + totals.subtotal;
        }
      }
    }

    return (taxByRate.entries
        .map((e) => TaxBucket(
              rate: e.key,
              taxCollected: e.value,
              taxableAmount: taxableByRate[e.key] ?? 0,
            ))
        .toList()
      ..sort((a, b) => a.rate.compareTo(b.rate)));
  }

  // ── 6. Top customers ──────────────────────────────────────────────────────

  static Future<List<TopCustomer>> getTopCustomers(
    DateTime from,
    DateTime to, {
    int limit = 500,
    String? currencyCode,
  }) async {
    final rows =
        await _loadRows(from: from, to: to, currencyCode: currencyCode);

    final byCustomer = <String, List<_InvRow>>{};
    for (final r in rows) {
      (byCustomer[r.customerKey] ??= []).add(r);
    }

    final result = byCustomer.entries.map((e) {
      double billed = 0, collected = 0, outstanding = 0;
      for (final r in e.value) {
        billed += r.total;
        collected += r.paid;
        outstanding += r.outstanding;
      }
      return TopCustomer(
        name: e.value.first.customerName,
        invoiceCount: e.value.length,
        billed: billed,
        collected: collected,
        outstanding: outstanding,
      );
    }).toList()
      ..sort((a, b) => b.billed.compareTo(a.billed));

    return result.take(limit).toList();
  }

  static Future<List<CustomerStatementCustomer>> getStatementCustomers({
    String? currencyCode,
  }) async {
    final db = await _db.database;
    final sb = StringBuffer(
      "type = 'Invoice' AND deleted_at IS NULL "
      "AND COALESCE(NULLIF(customer_id, ''), customer_name) IS NOT NULL",
    );
    final args = <Object?>[];
    if (currencyCode != null) {
      sb.write(' AND (currency_code = ? OR currency_code IS NULL)');
      args.add(currencyCode);
    }

    // Subquery so ORDER BY sees the alias on both SQLite and Postgres; MAX()
    // picks one name per customer deterministically (Postgres needs an
    // aggregate there).
    final rows = await db.rawQuery(
      'SELECT * FROM ('
      "SELECT COALESCE(NULLIF(customer_id, ''), customer_name) AS customer_key, "
      "MAX(COALESCE(NULLIF(customer_name, ''), 'Unknown')) AS customer_name, "
      'COUNT(*) AS invoice_count '
      'FROM invoices '
      'WHERE ${sb.toString()} '
      "GROUP BY COALESCE(NULLIF(customer_id, ''), customer_name)"
      ') grouped '
      'ORDER BY customer_name COLLATE NOCASE',
      args,
    );

    return rows
        .map((r) => CustomerStatementCustomer(
              key: CustomerIdentity.key(
                id: r['customer_key'] as String?,
                name: r['customer_name'] as String?,
              ),
              name: CustomerIdentity.displayName(r['customer_name'] as String?),
              invoiceCount: (r['invoice_count'] as num).toInt(),
            ))
        .toList();
  }

  static Future<List<CustomerStatement>> getCustomerStatements(
    String customerKey,
    DateTime from,
    DateTime to, {
    String? currencyCode,
  }) async {
    final rows = await _loadRows(
      customerKey: customerKey,
      currencyCode: currencyCode,
    );
    if (rows.isEmpty) return [];

    final db = await _db.database;
    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final byCurrency = <String, List<_InvRow>>{};
    for (final row in rows) {
      (byCurrency[row.currencyCode] ??= []).add(row);
    }

    final statements = <CustomerStatement>[];
    for (final entry in byCurrency.entries) {
      final currencyRows = entry.value;
      final ids = currencyRows.map((r) => r.id).toList();
      final paymentRows = await queryInChunks(
        ids,
        (chunk, ph) => db.rawQuery(
          'SELECT invoice_id, receipt_number, amount_paid, date_paid, '
          'payment_method, notes '
          'FROM invoice_payments WHERE invoice_id IN ($ph) '
          'ORDER BY date_paid ASC, rowid ASC',
          chunk,
        ),
      );
      final invoicesById = {for (final r in currencyRows) r.id: r};
      final drafts = <_StatementLineDraft>[];
      double opening = 0;
      double invoiced = 0;
      double paid = 0;
      double overdue = 0;

      for (final invoice in currencyRows) {
        if (invoice.date.compareTo(f) < 0) {
          opening += invoice.total;
        } else if (invoice.date.compareTo(t) <= 0) {
          invoiced += invoice.total;
          drafts.add(_StatementLineDraft(
            date: invoice.date,
            order: 0,
            type: 'Invoice',
            reference: invoice.id,
            description: 'Invoice raised',
            debit: invoice.total,
            credit: 0,
          ));
        }

        final dueDate = invoice.dueDate;
        if (InvoiceCalculator.isOverdue(
          dueDate: dueDate == null ? null : DateTime.tryParse(dueDate),
          outstanding: invoice.outstanding,
        )) {
          overdue += invoice.outstanding;
        }
      }

      for (final payment in paymentRows) {
        final invoice = invoicesById[payment['invoice_id'] as String];
        if (invoice == null) continue;
        final date = payment['date_paid'] as String? ?? '';
        final amount = (payment['amount_paid'] as num?)?.toDouble() ?? 0;
        if (date.compareTo(f) < 0) {
          opening -= amount;
        } else if (date.compareTo(t) <= 0) {
          paid += amount;
          final method = payment['payment_method'] as String?;
          drafts.add(_StatementLineDraft(
            date: date,
            order: 1,
            type: 'Payment',
            reference: payment['receipt_number'] as String? ?? invoice.id,
            description: method == null || method.isEmpty
                ? 'Payment for ${invoice.id}'
                : 'Payment for ${invoice.id} ($method)',
            debit: 0,
            credit: amount,
          ));
        }
      }

      drafts.sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        if (byDate != 0) return byDate;
        return a.order.compareTo(b.order);
      });

      var running = opening;
      final lines = drafts.map((draft) {
        running += draft.debit - draft.credit;
        return CustomerStatementLine(
          date: draft.date,
          type: draft.type,
          reference: draft.reference,
          description: draft.description,
          debit: draft.debit,
          credit: draft.credit,
          balance: running,
        );
      }).toList();

      statements.add(CustomerStatement(
        customerKey: customerKey,
        customerName: currencyRows.first.customerName,
        currencyCode: entry.key,
        currencySymbol: currencyRows.first.currencySymbol,
        openingBalance: opening,
        invoiced: invoiced,
        paid: paid,
        closingBalance: running,
        overdueBalance: overdue,
        lines: lines,
      ));
    }

    statements.sort((a, b) => a.currencyCode.compareTo(b.currencyCode));
    return statements;
  }

  // ── 7. Top products ───────────────────────────────────────────────────────

  static Future<List<TopProduct>> getTopProducts(
    DateTime from,
    DateTime to, {
    int limit = 500,
    String? currencyCode,
    bool rankByProfit = false,
  }) async {
    final db = await _db.database;
    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final ccFilter = currencyCode != null
        ? 'AND (i.currency_code = ? OR i.currency_code IS NULL) '
        : '';
    final args = <Object?>[
      if (currencyCode != null) currencyCode,
      f,
      t,
      limit,
    ];
    final orderBy = rankByProfit
        ? '(SUM($_invoiceItemTaxableNetSql) - SUM(ii.quantity * ii.product_purchase_price))'
        : 'revenue';
    final rows = await db.rawQuery(
      "SELECT ii.product_name, "
      "SUM(ii.quantity) AS units_sold, "
      "SUM($_invoiceItemTaxableNetSql) AS revenue, "
      "SUM($_invoiceItemDiscountSql) AS discount_given, "
      "SUM(ii.quantity * ii.product_purchase_price) AS cogs "
      "FROM invoice_items ii "
      "JOIN invoices i ON i.id = ii.invoice_id "
      "WHERE i.deleted_at IS NULL AND i.type = 'Invoice' "
      "AND (i.status IS NULL OR i.status != 'declined') "
      "$ccFilter"
      "AND i.date >= ? AND i.date <= ? "
      "GROUP BY ii.product_name ORDER BY $orderBy DESC LIMIT ?",
      args,
    );
    return rows
        .map((r) => TopProduct(
              name: r['product_name'] as String? ?? 'Unknown',
              unitsSold: (r['units_sold'] as num).toDouble(),
              revenue: (r['revenue'] as num).toDouble(),
              discountGiven: (r['discount_given'] as num).toDouble(),
              cogs: (r['cogs'] as num?)?.toDouble() ?? 0.0,
            ))
        .toList();
  }

  // ── 7b. Inventory valuation ───────────────────────────────────────────────
  // "Tracked" products = type='product' AND unlimited_stock=0 — the only rows
  // with a meaningful "capital blocked in stock" figure. Services and
  // unlimited-stock items are excluded from the totals (counted separately).

  static const _trackedProductWhere =
      "type = 'product' AND unlimited_stock = 0";

  static Future<InventoryValuationSummary>
      getInventoryValuationSummary() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(stock * purchase_price), 0) AS stock_value, '
      'COALESCE(SUM(stock * price), 0) AS retail_value, '
      'COALESCE(SUM(stock), 0) AS total_units, '
      'COUNT(*) AS product_count '
      'FROM products WHERE $_trackedProductWhere',
    );
    final excludedRows = await db.rawQuery(
      "SELECT COUNT(*) AS excluded_count FROM products "
      "WHERE NOT ($_trackedProductWhere)",
    );
    final r = rows.first;
    return InventoryValuationSummary(
      stockValue: (r['stock_value'] as num).toDouble(),
      retailValue: (r['retail_value'] as num).toDouble(),
      totalUnits: (r['total_units'] as num).toInt(),
      productCount: (r['product_count'] as num).toInt(),
      excludedCount: (excludedRows.first['excluded_count'] as num).toInt(),
    );
  }

  /// [limit] caps the row list for on-screen display; pass null for exports
  /// so the file always contains every tracked product, never a partial set.
  static Future<List<InventoryValuationRow>> getInventoryValuationRows({
    int? limit = 500,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT id, name, stock, purchase_price, price, unit FROM products '
      'WHERE $_trackedProductWhere '
      'ORDER BY (stock * purchase_price) DESC'
      '${limit != null ? ' LIMIT $limit' : ''}',
    );
    return rows
        .map((r) => InventoryValuationRow(
              productId: r['id'] as String? ?? '',
              name: r['name'] as String? ?? '',
              stock: (r['stock'] as num?)?.toInt() ?? 0,
              purchasePrice: (r['purchase_price'] as num?)?.toDouble() ?? 0.0,
              price: (r['price'] as num?)?.toDouble() ?? 0.0,
              unit: r['unit'] as String? ?? '',
            ))
        .toList();
  }

  // ── 8. Quotation conversion ───────────────────────────────────────────────

  static Future<QuotationStats> getQuotationStats(
    DateTime from,
    DateTime to, {
    String? currencyCode,
  }) async {
    final db = await _db.database;
    final f = AppDate.dateKeyStart(from);
    final t = AppDate.dateKeyEnd(to);
    final currencyFilter = currencyCode != null
        ? 'AND (currency_code = ? OR currency_code IS NULL) '
        : '';
    final args = <Object?>[
      if (currencyCode != null) currencyCode,
      f,
      t,
    ];

    final qr = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices "
      "WHERE type = 'Quotation' AND deleted_at IS NULL "
      "$currencyFilter"
      "AND date >= ? AND date <= ?",
      args,
    );
    final quotationsIssued = (qr.first['cnt'] as int?) ?? 0;

    final ir = await db.rawQuery(
      "SELECT COUNT(*) AS cnt FROM invoices "
      "WHERE type = 'Invoice' AND deleted_at IS NULL "
      "$currencyFilter"
      "AND date >= ? AND date <= ?",
      args,
    );
    final invoicesInPeriod = (ir.first['cnt'] as int?) ?? 0;

    final rate = quotationsIssued == 0
        ? 0.0
        : (invoicesInPeriod / quotationsIssued * 100).clamp(0.0, 100.0);

    return QuotationStats(
      quotationsIssued: quotationsIssued,
      invoicesInPeriod: invoicesInPeriod,
      conversionRate: rate,
    );
  }

  // ── 9. Invoice status list ─────────────────────────────────────────────────

  static Future<List<InvoiceStatusRow>> getInvoiceStatusList(
    DateTime from,
    DateTime to, {
    String? currencyCode,
  }) async {
    final rows = await _loadRows(
      from: from,
      to: to,
      currencyCode: currencyCode,
    );
    final now = DateTime.now();
    final result = rows.map((r) {
      final dueDate = r.dueDate != null ? DateTime.tryParse(r.dueDate!) : null;
      final noDueDate = r.dueDate == null;
      final daysOverdue =
          InvoiceCalculator.daysOverdue(dueDate: dueDate, asOf: now);

      final status = switch (
          InvoiceCalculator.paymentStatus(total: r.total, paid: r.paid)) {
        PaymentStatus.paid => 'Paid',
        PaymentStatus.partial => 'Partial',
        PaymentStatus.unpaid => 'Unpaid',
      };

      final isOverdue = InvoiceCalculator.isOverdue(
        dueDate: dueDate,
        outstanding: r.outstanding,
        asOf: now,
      );

      return InvoiceStatusRow(
        id: r.id,
        date: r.date,
        dueDate: r.dueDate,
        customerName: r.customerName,
        total: r.total,
        paid: r.paid,
        outstanding: r.outstanding,
        daysOverdue: daysOverdue,
        hasNoDueDate: noDueDate,
        status: status,
        isOverdue: isOverdue,
      );
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return result;
  }
}
