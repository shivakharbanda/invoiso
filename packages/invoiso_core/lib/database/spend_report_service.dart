import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/spend_report_models.dart';
import 'package:invoiso_core/utils/app_date.dart';

import 'database_helper.dart';
import 'expense_service.dart';
import 'report_service.dart';

/// Spend reports. Money is INR (`inr_amount`: what was actually paid, or the
/// INR value of usage). Aggregation happens in Dart over the period's rows —
/// a few thousand entries a year at most — so results are identical on
/// SQLite and Postgres.
class SpendReportService {
  static final _dbHelper = DatabaseHelper();

  /// Revenue side of the reports is in the invoice currency; spend is INR.
  static const _revenueCurrency = 'INR';

  static Future<List<Expense>> _inRange(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final rows = await db.query('expenses',
        where: 'deleted_at IS NULL AND date >= ? AND date <= ?',
        whereArgs: [AppDate.dateKeyStart(from), AppDate.dateKeyEnd(to)]);
    return rows.map(Expense.fromMap).toList();
  }

  /// INR value of an entry's tax (tax is entered in the billing currency).
  static double _taxInr(Expense e) {
    if (e.taxAmount == 0 || e.total == 0) return 0;
    return e.currencyCode == 'INR' ? e.taxAmount : e.inrAmount * e.taxAmount / e.total;
  }

  static bool _claimable(Expense e) =>
      e.isCashOut && (e.taxKind == 'gst' || e.taxKind == 'igst' || e.taxKind == 'rcm');

  static Future<SpendTotals> getTotals(DateTime from, DateTime to) async {
    final entries = await _inRange(from, to);
    var cash = 0.0, cost = 0.0, tax = 0.0;
    for (final e in entries) {
      if (e.isCashOut) cash += e.inrAmount;
      if (e.isCost) cost += e.inrAmount;
      if (_claimable(e)) tax += _taxInr(e);
    }
    return SpendTotals(
        cashOut: cash, cost: cost, inputTax: tax, entryCount: entries.length);
  }

  /// [groupBy]: `vendor` | `category` | `client` | `project` | `type`.
  static Future<List<SpendGroupRow>> getSpendBy(
      String groupBy, DateTime from, DateTime to) async {
    final entries = await _inRange(from, to);
    final labels = await _labels(groupBy);
    final acc = <String, ({double cash, double cost, int n})>{};
    final names = <String, String>{};
    for (final e in entries) {
      final key = switch (groupBy) {
            'vendor' => e.vendorId ?? 'name:${e.vendorName}',
            'category' => e.categoryId,
            'client' => e.customerId,
            'project' => e.projectId,
            'type' => e.entryType,
            _ => throw ArgumentError('Unknown groupBy $groupBy'),
          } ??
          '';
      if (groupBy == 'vendor') names[key] = e.vendorName;
      final prev = acc[key] ?? (cash: 0.0, cost: 0.0, n: 0);
      acc[key] = (
        cash: prev.cash + (e.isCashOut ? e.inrAmount : 0),
        cost: prev.cost + (e.isCost ? e.inrAmount : 0),
        n: prev.n + 1,
      );
    }
    final rows = [
      for (final MapEntry(:key, :value) in acc.entries)
        SpendGroupRow(
          key: key,
          label: key.isEmpty
              ? '(none)'
              : labels[key] ?? names[key] ?? key,
          cashOut: value.cash,
          cost: value.cost,
          entryCount: value.n,
        ),
    ]..sort((a, b) => (b.cashOut + b.cost).compareTo(a.cashOut + a.cost));
    return rows;
  }

  static Future<Map<String, String>> _labels(String groupBy) async {
    final db = await _dbHelper.database;
    switch (groupBy) {
      case 'category':
        return {
          for (final c in await ExpenseService.getCategories()) c.id: c.name,
          for (final r in await db.query('expense_categories'))
            r['id'] as String: r['name'] as String,
        };
      case 'client':
        return {
          for (final r in await db.query('customers', columns: ['id', 'name']))
            r['id'] as String: r['name'] as String? ?? '',
        };
      case 'project':
        return {
          for (final r in await db.query('projects', columns: ['id', 'name']))
            r['id'] as String: r['name'] as String,
        };
      case 'type':
        return const {
          Expense.typeTopup: 'Wallet top-ups',
          Expense.typeUsage: 'Usage',
          Expense.typeInvoice: 'Vendor invoices',
          Expense.typeSubscription: 'Subscriptions',
          Expense.typeOther: 'Other',
        };
      default:
        return const {};
    }
  }

  static Future<List<MonthlySpendPoint>> getMonthlySpend(
      DateTime from, DateTime to) async {
    final entries = await _inRange(from, to);
    final acc = <String, (double, double)>{};
    // Every month in range, so charts show gaps as zero.
    for (var m = DateTime(from.year, from.month);
        !m.isAfter(DateTime(to.year, to.month));
        m = DateTime(m.year, m.month + 1)) {
      acc[AppDate.dateKey(m).substring(0, 7)] = (0, 0);
    }
    for (final e in entries) {
      final key = AppDate.dateKey(e.date).substring(0, 7);
      final (cash, cost) = acc[key] ?? (0, 0);
      acc[key] = (
        cash + (e.isCashOut ? e.inrAmount : 0),
        cost + (e.isCost ? e.inrAmount : 0),
      );
    }
    return [
      for (final key in acc.keys.toList()..sort())
        MonthlySpendPoint(month: key, cashOut: acc[key]!.$1, cost: acc[key]!.$2),
    ];
  }

  /// All-time prepaid balance per vendor: top-ups minus usage, in the
  /// vendor's billing currency (pre-tax amounts — the wallet credit).
  static Future<List<WalletBalance>> getWalletBalances() async {
    final db = await _dbHelper.database;
    final vendors = await db.query('suppliers', where: 'deleted_at IS NULL');
    final rows = await db.query('expenses',
        where: "deleted_at IS NULL AND entry_type IN ('topup', 'usage') "
            'AND vendor_id IS NOT NULL',
        orderBy: 'date');
    final byVendor = <String, List<Expense>>{};
    for (final r in rows) {
      final e = Expense.fromMap(r);
      byVendor.putIfAbsent(e.vendorId!, () => []).add(e);
    }
    final out = <WalletBalance>[];
    for (final v in vendors) {
      final id = v['id'] as String;
      final entries = byVendor[id] ?? const <Expense>[];
      final prepaid = v['billing_model'] == 'prepaid';
      if (!prepaid && entries.isEmpty) continue;
      final currency = v['default_currency'] as String? ??
          (entries.isEmpty ? 'INR' : entries.first.currencyCode);
      var topped = 0.0, used = 0.0;
      String? lastTopup;
      for (final e in entries.where((e) => e.currencyCode == currency)) {
        if (e.entryType == Expense.typeTopup) {
          topped += e.amount;
          lastTopup = e.date.toIso8601String();
        } else {
          used += e.amount;
        }
      }
      final threshold = (v['low_balance_threshold'] as num?)?.toDouble();
      final balance = topped - used;
      out.add(WalletBalance(
        vendorId: id,
        vendorName: v['name'] as String? ?? '',
        currencyCode: currency,
        toppedUp: topped,
        used: used,
        balance: balance,
        lowBalanceThreshold: threshold,
        isLow: threshold != null && balance < threshold,
        lastTopupDate: lastTopup,
      ));
    }
    out.sort((a, b) => a.vendorName.toLowerCase().compareTo(b.vendorName.toLowerCase()));
    return out;
  }

  /// Revenue vs. cost per client: invoiced revenue (tax-exclusive) and
  /// product COGS from invoices, plus vendor costs tagged to the client.
  static Future<List<ClientProfitRow>> getClientProfitability(
      DateTime from, DateTime to) async {
    final revenue = await ReportService.getRevenueByCustomer(from, to,
        currencyCode: _revenueCurrency);
    final costs = <String, double>{};
    for (final e in await _inRange(from, to)) {
      if (e.isCost && e.customerId != null && e.customerId!.isNotEmpty) {
        costs[e.customerId!] = (costs[e.customerId!] ?? 0) + e.inrAmount;
      }
    }
    final db = await _dbHelper.database;
    final customerNames = {
      for (final r in await db.query('customers', columns: ['id', 'name']))
        r['id'] as String: r['name'] as String? ?? '',
    };
    final keys = {...revenue.keys, ...costs.keys};
    final rows = [
      for (final k in keys)
        ClientProfitRow(
          customerKey: k,
          customerName: revenue[k]?.name ?? customerNames[k] ?? k,
          revenue: revenue[k]?.revenue ?? 0,
          cogs: revenue[k]?.cogs ?? 0,
          vendorCost: costs[k] ?? 0,
        ),
    ]..sort((a, b) => b.revenue.compareTo(a.revenue));
    return rows;
  }

  static Future<ProfitAndLoss> getProfitAndLoss(DateTime from, DateTime to) async {
    final revenue = await ReportService.getRevenueByCustomer(from, to,
        currencyCode: _revenueCurrency);
    final totals = await getTotals(from, to);
    return ProfitAndLoss(
      revenue: revenue.values.fold(0.0, (s, r) => s + r.revenue),
      cogs: revenue.values.fold(0.0, (s, r) => s + r.cogs),
      vendorCashOut: totals.cashOut,
      vendorCost: totals.cost,
    );
  }

  /// GST/IGST/RCM paid per vendor and tax kind, for the input-credit claim.
  static Future<List<InputTaxRow>> getInputTax(DateTime from, DateTime to) async {
    final db = await _dbHelper.database;
    final gstins = {
      for (final r in await db.query('suppliers', columns: ['id', 'gstin']))
        r['id'] as String: r['gstin'] as String? ?? '',
    };
    final acc = <String, ({String vendor, String gstin, String kind, double taxable, double tax, int n})>{};
    for (final e in await _inRange(from, to)) {
      if (!_claimable(e)) continue;
      final key = '${e.vendorId ?? e.vendorName}|${e.taxKind}';
      final tax = _taxInr(e);
      final prev = acc[key];
      acc[key] = (
        vendor: e.vendorName,
        gstin: gstins[e.vendorId] ?? '',
        kind: e.taxKind,
        taxable: (prev?.taxable ?? 0) + (e.inrAmount - tax),
        tax: (prev?.tax ?? 0) + tax,
        n: (prev?.n ?? 0) + 1,
      );
    }
    return [
      for (final r in acc.values)
        InputTaxRow(
          vendorName: r.vendor,
          gstin: r.gstin,
          taxKind: r.kind,
          taxableInr: r.taxable,
          taxInr: r.tax,
          entryCount: r.n,
        ),
    ]..sort((a, b) => b.taxInr.compareTo(a.taxInr));
  }
}
