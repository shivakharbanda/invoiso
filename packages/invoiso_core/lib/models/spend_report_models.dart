/// Totals for a period. All money in INR (what was actually paid / valued).
class SpendTotals {
  /// Top-ups + vendor invoices + subscriptions + other (money that left).
  final double cashOut;

  /// Usage + vendor invoices + subscriptions + other (cost consumed).
  final double cost;

  /// GST/IGST paid that can be claimed as input tax credit (INR).
  final double inputTax;
  final int entryCount;

  const SpendTotals({
    required this.cashOut,
    required this.cost,
    required this.inputTax,
    required this.entryCount,
  });

  Map<String, dynamic> toJson() => {
        'cashOut': cashOut,
        'cost': cost,
        'inputTax': inputTax,
        'entryCount': entryCount,
      };

  factory SpendTotals.fromJson(Map<String, dynamic> j) => SpendTotals(
        cashOut: (j['cashOut'] as num).toDouble(),
        cost: (j['cost'] as num).toDouble(),
        inputTax: (j['inputTax'] as num).toDouble(),
        entryCount: (j['entryCount'] as num).toInt(),
      );
}

/// One row of a spend breakdown (by vendor, category, client or project).
class SpendGroupRow {
  final String key;
  final String label;
  final double cashOut;
  final double cost;
  final int entryCount;

  const SpendGroupRow({
    required this.key,
    required this.label,
    required this.cashOut,
    required this.cost,
    required this.entryCount,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'cashOut': cashOut,
        'cost': cost,
        'entryCount': entryCount,
      };

  factory SpendGroupRow.fromJson(Map<String, dynamic> j) => SpendGroupRow(
        key: j['key'] as String,
        label: j['label'] as String,
        cashOut: (j['cashOut'] as num).toDouble(),
        cost: (j['cost'] as num).toDouble(),
        entryCount: (j['entryCount'] as num).toInt(),
      );
}

class MonthlySpendPoint {
  /// `YYYY-MM`
  final String month;
  final double cashOut;
  final double cost;

  const MonthlySpendPoint({
    required this.month,
    required this.cashOut,
    required this.cost,
  });

  Map<String, dynamic> toJson() => {
        'month': month,
        'cashOut': cashOut,
        'cost': cost,
      };

  factory MonthlySpendPoint.fromJson(Map<String, dynamic> j) => MonthlySpendPoint(
        month: j['month'] as String,
        cashOut: (j['cashOut'] as num).toDouble(),
        cost: (j['cost'] as num).toDouble(),
      );
}

/// Prepaid wallet of one vendor, in the vendor's billing currency.
class WalletBalance {
  final String vendorId;
  final String vendorName;
  final String currencyCode;
  final double toppedUp;
  final double used;
  final double balance;
  final double? lowBalanceThreshold;
  final bool isLow;
  final String? lastTopupDate;

  const WalletBalance({
    required this.vendorId,
    required this.vendorName,
    required this.currencyCode,
    required this.toppedUp,
    required this.used,
    required this.balance,
    this.lowBalanceThreshold,
    required this.isLow,
    this.lastTopupDate,
  });

  Map<String, dynamic> toJson() => {
        'vendorId': vendorId,
        'vendorName': vendorName,
        'currencyCode': currencyCode,
        'toppedUp': toppedUp,
        'used': used,
        'balance': balance,
        'lowBalanceThreshold': lowBalanceThreshold,
        'isLow': isLow,
        'lastTopupDate': lastTopupDate,
      };

  factory WalletBalance.fromJson(Map<String, dynamic> j) => WalletBalance(
        vendorId: j['vendorId'] as String,
        vendorName: j['vendorName'] as String,
        currencyCode: j['currencyCode'] as String,
        toppedUp: (j['toppedUp'] as num).toDouble(),
        used: (j['used'] as num).toDouble(),
        balance: (j['balance'] as num).toDouble(),
        lowBalanceThreshold: j['lowBalanceThreshold'] == null ? null : (j['lowBalanceThreshold'] as num).toDouble(),
        isLow: j['isLow'] as bool,
        lastTopupDate: j['lastTopupDate'] as String?,
      );
}

/// Revenue earned from a client vs. what serving them cost.
class ClientProfitRow {
  final String customerKey;
  final String customerName;

  /// Tax-exclusive invoiced revenue (net of invoice discounts).
  final double revenue;

  /// Cost of products sold on those invoices (purchase price).
  final double cogs;

  /// Vendor costs tagged to this client (usage, invoices, subscriptions, other).
  final double vendorCost;

  const ClientProfitRow({
    required this.customerKey,
    required this.customerName,
    required this.revenue,
    required this.cogs,
    required this.vendorCost,
  });

  double get profit => revenue - cogs - vendorCost;

  double get marginPercent => revenue == 0 ? 0 : profit / revenue * 100;

  Map<String, dynamic> toJson() => {
        'customerKey': customerKey,
        'customerName': customerName,
        'revenue': revenue,
        'cogs': cogs,
        'vendorCost': vendorCost,
      };

  factory ClientProfitRow.fromJson(Map<String, dynamic> j) => ClientProfitRow(
        customerKey: j['customerKey'] as String,
        customerName: j['customerName'] as String,
        revenue: (j['revenue'] as num).toDouble(),
        cogs: (j['cogs'] as num).toDouble(),
        vendorCost: (j['vendorCost'] as num).toDouble(),
      );
}

/// Profit & loss for a period (INR).
class ProfitAndLoss {
  /// Tax-exclusive invoiced revenue.
  final double revenue;
  final double cogs;

  /// Vendor cash out in the period (cash basis).
  final double vendorCashOut;

  /// Vendor cost consumed in the period (usage basis).
  final double vendorCost;

  const ProfitAndLoss({
    required this.revenue,
    required this.cogs,
    required this.vendorCashOut,
    required this.vendorCost,
  });

  double get netCashBasis => revenue - cogs - vendorCashOut;

  double get netUsageBasis => revenue - cogs - vendorCost;

  Map<String, dynamic> toJson() => {
        'revenue': revenue,
        'cogs': cogs,
        'vendorCashOut': vendorCashOut,
        'vendorCost': vendorCost,
      };

  factory ProfitAndLoss.fromJson(Map<String, dynamic> j) => ProfitAndLoss(
        revenue: (j['revenue'] as num).toDouble(),
        cogs: (j['cogs'] as num).toDouble(),
        vendorCashOut: (j['vendorCashOut'] as num).toDouble(),
        vendorCost: (j['vendorCost'] as num).toDouble(),
      );
}

/// Input tax per vendor for the GST return.
class InputTaxRow {
  final String vendorName;
  final String gstin;
  final String taxKind;
  final double taxableInr;
  final double taxInr;
  final int entryCount;

  const InputTaxRow({
    required this.vendorName,
    required this.gstin,
    required this.taxKind,
    required this.taxableInr,
    required this.taxInr,
    required this.entryCount,
  });

  Map<String, dynamic> toJson() => {
        'vendorName': vendorName,
        'gstin': gstin,
        'taxKind': taxKind,
        'taxableInr': taxableInr,
        'taxInr': taxInr,
        'entryCount': entryCount,
      };

  factory InputTaxRow.fromJson(Map<String, dynamic> j) => InputTaxRow(
        vendorName: j['vendorName'] as String,
        gstin: j['gstin'] as String,
        taxKind: j['taxKind'] as String,
        taxableInr: (j['taxableInr'] as num).toDouble(),
        taxInr: (j['taxInr'] as num).toDouble(),
        entryCount: (j['entryCount'] as num).toInt(),
      );
}
