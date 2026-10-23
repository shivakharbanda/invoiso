class RevenueKpi {
  final int invoiceCount;
  final double billed;
  final double collected;
  final double outstanding;
  final double avgInvoiceValue;
  final double profit;
  // Profit scaled by each invoice's collected fraction — the realized
  // (cash-basis) counterpart to [profit].
  final double realizedProfit;

  const RevenueKpi({
    required this.invoiceCount,
    required this.billed,
    required this.collected,
    required this.outstanding,
    required this.avgInvoiceValue,
    this.profit = 0.0,
    this.realizedProfit = 0.0,
  });

  static const RevenueKpi empty = RevenueKpi(
    invoiceCount: 0,
    billed: 0,
    collected: 0,
    outstanding: 0,
    avgInvoiceValue: 0,
  );

  Map<String, dynamic> toJson() => {
        'invoiceCount': invoiceCount,
        'billed': billed,
        'collected': collected,
        'outstanding': outstanding,
        'avgInvoiceValue': avgInvoiceValue,
        'profit': profit,
        'realizedProfit': realizedProfit,
      };

  factory RevenueKpi.fromJson(Map<String, dynamic> j) => RevenueKpi(
        invoiceCount: (j['invoiceCount'] as num).toInt(),
        billed: (j['billed'] as num).toDouble(),
        collected: (j['collected'] as num).toDouble(),
        outstanding: (j['outstanding'] as num).toDouble(),
        avgInvoiceValue: (j['avgInvoiceValue'] as num).toDouble(),
        profit: (j['profit'] as num).toDouble(),
        realizedProfit: (j['realizedProfit'] as num).toDouble(),
      );
}

class MonthlyPoint {
  final String month;
  final double billed;
  final double collected;
  final double profit;
  final int invoiceCount;
  final double netSales;
  final double cogs;
  final double outstanding;

  const MonthlyPoint({
    required this.month,
    required this.billed,
    required this.collected,
    this.profit = 0.0,
    this.invoiceCount = 0,
    this.netSales = 0.0,
    this.cogs = 0.0,
    this.outstanding = 0.0,
  });

  double get marginPercent => netSales == 0 ? 0.0 : (profit / netSales) * 100;

  Map<String, dynamic> toJson() => {
        'month': month,
        'billed': billed,
        'collected': collected,
        'profit': profit,
        'invoiceCount': invoiceCount,
        'netSales': netSales,
        'cogs': cogs,
        'outstanding': outstanding,
      };

  factory MonthlyPoint.fromJson(Map<String, dynamic> j) => MonthlyPoint(
        month: j['month'] as String,
        billed: (j['billed'] as num).toDouble(),
        collected: (j['collected'] as num).toDouble(),
        profit: (j['profit'] as num).toDouble(),
        invoiceCount: (j['invoiceCount'] as num).toInt(),
        netSales: (j['netSales'] as num).toDouble(),
        cogs: (j['cogs'] as num).toDouble(),
        outstanding: (j['outstanding'] as num).toDouble(),
      );
}

class DailyPoint {
  final String date;
  final int invoiceCount;
  final double billed;
  final double cogs;
  // Cash/UPI exchange feature (0 when it's off). cash / upiBank: net change
  // from ledger movements (exchanges, expenses, ...); paidCash / paidUpi:
  // invoice payments received. Together = the accounts' net change that day.
  final double cash;
  final double upiBank;
  final double paidCash;
  final double paidUpi;
  // Exchange service fees that day and number of exchanges.
  final double serviceIncome;
  final int exchangeCount;

  const DailyPoint({
    required this.date,
    required this.invoiceCount,
    required this.billed,
    this.cogs = 0.0,
    this.cash = 0.0,
    this.upiBank = 0.0,
    this.paidCash = 0.0,
    this.paidUpi = 0.0,
    this.serviceIncome = 0.0,
    this.exchangeCount = 0,
  });

  double get profit => billed - cogs;

  /// Invoice profit plus exchange service fees.
  double get totalProfit => profit + serviceIncome;

  double get marginPercent => billed == 0 ? 0.0 : (profit / billed) * 100;

  bool get hasInvoiceActivity =>
      invoiceCount > 0 || paidCash != 0 || paidUpi != 0;

  bool get hasExchangeActivity =>
      exchangeCount > 0 || cash != 0 || upiBank != 0 || serviceIncome != 0;

  Map<String, dynamic> toJson() => {
        'date': date,
        'invoiceCount': invoiceCount,
        'billed': billed,
        'cogs': cogs,
        'cash': cash,
        'upiBank': upiBank,
        'paidCash': paidCash,
        'paidUpi': paidUpi,
        'serviceIncome': serviceIncome,
        'exchangeCount': exchangeCount,
      };

  factory DailyPoint.fromJson(Map<String, dynamic> j) => DailyPoint(
        date: j['date'] as String,
        invoiceCount: (j['invoiceCount'] as num).toInt(),
        billed: (j['billed'] as num).toDouble(),
        cogs: (j['cogs'] as num).toDouble(),
        cash: (j['cash'] as num).toDouble(),
        upiBank: (j['upiBank'] as num).toDouble(),
        paidCash: (j['paidCash'] as num).toDouble(),
        paidUpi: (j['paidUpi'] as num).toDouble(),
        serviceIncome: (j['serviceIncome'] as num).toDouble(),
        exchangeCount: (j['exchangeCount'] as num).toInt(),
      );
}

/// One Daily Report table line: a day's invoices, or its cash-exchange
/// ledger activity ([exchange]).
typedef DailyLine = ({DailyPoint d, bool exchange});

class StatusBreakdown {
  final int paid;
  final int partial;
  final int unpaid;

  const StatusBreakdown({
    required this.paid,
    required this.partial,
    required this.unpaid,
  });

  int get total => paid + partial + unpaid;

  static const StatusBreakdown empty =
      StatusBreakdown(paid: 0, partial: 0, unpaid: 0);

  Map<String, dynamic> toJson() => {
        'paid': paid,
        'partial': partial,
        'unpaid': unpaid,
      };

  factory StatusBreakdown.fromJson(Map<String, dynamic> j) => StatusBreakdown(
        paid: (j['paid'] as num).toInt(),
        partial: (j['partial'] as num).toInt(),
        unpaid: (j['unpaid'] as num).toInt(),
      );
}

class AgedReceivable {
  final String invoiceId;
  final String customerName;
  final double outstanding;
  final int daysOverdue;
  final bool hasNoDueDate;

  const AgedReceivable({
    required this.invoiceId,
    required this.customerName,
    required this.outstanding,
    required this.daysOverdue,
    this.hasNoDueDate = false,
  });

  Map<String, dynamic> toJson() => {
        'invoiceId': invoiceId,
        'customerName': customerName,
        'outstanding': outstanding,
        'daysOverdue': daysOverdue,
        'hasNoDueDate': hasNoDueDate,
      };

  factory AgedReceivable.fromJson(Map<String, dynamic> j) => AgedReceivable(
        invoiceId: j['invoiceId'] as String,
        customerName: j['customerName'] as String,
        outstanding: (j['outstanding'] as num).toDouble(),
        daysOverdue: (j['daysOverdue'] as num).toInt(),
        hasNoDueDate: j['hasNoDueDate'] as bool,
      );
}

/// One customer's outstanding balance split into aging buckets, for the
/// A/R Aging Summary. Bucket boundaries match [AgedReceivable]'s detail rows.
class AgedReceivableSummaryRow {
  final String customerName;
  final double current;
  final double d0to30;
  final double d31to60;
  final double d61to90;
  final double d90plus;
  final double noDueDate;

  const AgedReceivableSummaryRow({
    required this.customerName,
    this.current = 0.0,
    this.d0to30 = 0.0,
    this.d31to60 = 0.0,
    this.d61to90 = 0.0,
    this.d90plus = 0.0,
    this.noDueDate = 0.0,
  });

  double get total =>
      current + d0to30 + d31to60 + d61to90 + d90plus + noDueDate;

  Map<String, dynamic> toJson() => {
        'customerName': customerName,
        'current': current,
        'd0to30': d0to30,
        'd31to60': d31to60,
        'd61to90': d61to90,
        'd90plus': d90plus,
        'noDueDate': noDueDate,
      };

  factory AgedReceivableSummaryRow.fromJson(Map<String, dynamic> j) =>
      AgedReceivableSummaryRow(
        customerName: j['customerName'] as String,
        current: (j['current'] as num).toDouble(),
        d0to30: (j['d0to30'] as num).toDouble(),
        d31to60: (j['d31to60'] as num).toDouble(),
        d61to90: (j['d61to90'] as num).toDouble(),
        d90plus: (j['d90plus'] as num).toDouble(),
        noDueDate: (j['noDueDate'] as num).toDouble(),
      );
}

class TaxBucket {
  final double rate;
  final double taxCollected;
  final double taxableAmount;

  const TaxBucket({
    required this.rate,
    required this.taxCollected,
    this.taxableAmount = 0.0,
  });

  double get gross => taxableAmount + taxCollected;

  Map<String, dynamic> toJson() => {
        'rate': rate,
        'taxCollected': taxCollected,
        'taxableAmount': taxableAmount,
      };

  factory TaxBucket.fromJson(Map<String, dynamic> j) => TaxBucket(
        rate: (j['rate'] as num).toDouble(),
        taxCollected: (j['taxCollected'] as num).toDouble(),
        taxableAmount: (j['taxableAmount'] as num).toDouble(),
      );
}

class TopCustomer {
  final String name;
  final int invoiceCount;
  final double billed;
  final double collected;
  final double outstanding;

  const TopCustomer({
    required this.name,
    required this.invoiceCount,
    required this.billed,
    required this.collected,
    required this.outstanding,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'invoiceCount': invoiceCount,
        'billed': billed,
        'collected': collected,
        'outstanding': outstanding,
      };

  factory TopCustomer.fromJson(Map<String, dynamic> j) => TopCustomer(
        name: j['name'] as String,
        invoiceCount: (j['invoiceCount'] as num).toInt(),
        billed: (j['billed'] as num).toDouble(),
        collected: (j['collected'] as num).toDouble(),
        outstanding: (j['outstanding'] as num).toDouble(),
      );
}

class CustomerStatementCustomer {
  final String key;
  final String name;
  final int invoiceCount;

  const CustomerStatementCustomer({
    required this.key,
    required this.name,
    required this.invoiceCount,
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'invoiceCount': invoiceCount,
      };

  factory CustomerStatementCustomer.fromJson(Map<String, dynamic> j) =>
      CustomerStatementCustomer(
        key: j['key'] as String,
        name: j['name'] as String,
        invoiceCount: (j['invoiceCount'] as num).toInt(),
      );
}

class CustomerStatementLine {
  final String date;
  final String type;
  final String reference;
  final String description;
  final double debit;
  final double credit;
  final double balance;

  const CustomerStatementLine({
    required this.date,
    required this.type,
    required this.reference,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
  });

  Map<String, dynamic> toJson() => {
        'date': date,
        'type': type,
        'reference': reference,
        'description': description,
        'debit': debit,
        'credit': credit,
        'balance': balance,
      };

  factory CustomerStatementLine.fromJson(Map<String, dynamic> j) =>
      CustomerStatementLine(
        date: j['date'] as String,
        type: j['type'] as String,
        reference: j['reference'] as String,
        description: j['description'] as String,
        debit: (j['debit'] as num).toDouble(),
        credit: (j['credit'] as num).toDouble(),
        balance: (j['balance'] as num).toDouble(),
      );
}

class CustomerStatement {
  final String customerKey;
  final String customerName;
  final String currencyCode;
  final String currencySymbol;
  final double openingBalance;
  final double invoiced;
  final double paid;
  final double closingBalance;
  final double overdueBalance;
  final List<CustomerStatementLine> lines;

  const CustomerStatement({
    required this.customerKey,
    required this.customerName,
    required this.currencyCode,
    required this.currencySymbol,
    required this.openingBalance,
    required this.invoiced,
    required this.paid,
    required this.closingBalance,
    required this.overdueBalance,
    required this.lines,
  });

  Map<String, dynamic> toJson() => {
        'customerKey': customerKey,
        'customerName': customerName,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'openingBalance': openingBalance,
        'invoiced': invoiced,
        'paid': paid,
        'closingBalance': closingBalance,
        'overdueBalance': overdueBalance,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory CustomerStatement.fromJson(Map<String, dynamic> j) =>
      CustomerStatement(
        customerKey: j['customerKey'] as String,
        customerName: j['customerName'] as String,
        currencyCode: j['currencyCode'] as String,
        currencySymbol: j['currencySymbol'] as String,
        openingBalance: (j['openingBalance'] as num).toDouble(),
        invoiced: (j['invoiced'] as num).toDouble(),
        paid: (j['paid'] as num).toDouble(),
        closingBalance: (j['closingBalance'] as num).toDouble(),
        overdueBalance: (j['overdueBalance'] as num).toDouble(),
        lines: [
          for (final e in j['lines'] as List)
            CustomerStatementLine.fromJson((e as Map).cast<String, dynamic>())
        ],
      );
}

class TopProduct {
  final String name;
  final double unitsSold;
  final double revenue;
  final double discountGiven;
  final double cogs;

  const TopProduct({
    required this.name,
    required this.unitsSold,
    required this.revenue,
    required this.discountGiven,
    this.cogs = 0.0,
  });

  double get profit => revenue - cogs;

  double get marginPercent => revenue == 0 ? 0.0 : (profit / revenue) * 100;

  Map<String, dynamic> toJson() => {
        'name': name,
        'unitsSold': unitsSold,
        'revenue': revenue,
        'discountGiven': discountGiven,
        'cogs': cogs,
      };

  factory TopProduct.fromJson(Map<String, dynamic> j) => TopProduct(
        name: j['name'] as String,
        unitsSold: (j['unitsSold'] as num).toDouble(),
        revenue: (j['revenue'] as num).toDouble(),
        discountGiven: (j['discountGiven'] as num).toDouble(),
        cogs: (j['cogs'] as num).toDouble(),
      );
}

class InventoryValuationSummary {
  final double stockValue;
  final double retailValue;
  final int totalUnits;
  final int productCount;
  final int excludedCount;

  const InventoryValuationSummary({
    required this.stockValue,
    required this.retailValue,
    required this.totalUnits,
    required this.productCount,
    required this.excludedCount,
  });

  double get lockedProfit => retailValue - stockValue;

  static const empty = InventoryValuationSummary(
    stockValue: 0,
    retailValue: 0,
    totalUnits: 0,
    productCount: 0,
    excludedCount: 0,
  );

  Map<String, dynamic> toJson() => {
        'stockValue': stockValue,
        'retailValue': retailValue,
        'totalUnits': totalUnits,
        'productCount': productCount,
        'excludedCount': excludedCount,
      };

  factory InventoryValuationSummary.fromJson(Map<String, dynamic> j) =>
      InventoryValuationSummary(
        stockValue: (j['stockValue'] as num).toDouble(),
        retailValue: (j['retailValue'] as num).toDouble(),
        totalUnits: (j['totalUnits'] as num).toInt(),
        productCount: (j['productCount'] as num).toInt(),
        excludedCount: (j['excludedCount'] as num).toInt(),
      );
}

class InventoryValuationRow {
  final String productId;
  final String name;
  final int stock;
  final double purchasePrice;
  final double price;
  final String unit;

  const InventoryValuationRow({
    required this.productId,
    required this.name,
    required this.stock,
    required this.purchasePrice,
    required this.price,
    required this.unit,
  });

  double get stockValue => stock * purchasePrice;

  double get retailValue => stock * price;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'stock': stock,
        'purchasePrice': purchasePrice,
        'price': price,
        'unit': unit,
      };

  factory InventoryValuationRow.fromJson(Map<String, dynamic> j) =>
      InventoryValuationRow(
        productId: j['productId'] as String,
        name: j['name'] as String,
        stock: (j['stock'] as num).toInt(),
        purchasePrice: (j['purchasePrice'] as num).toDouble(),
        price: (j['price'] as num).toDouble(),
        unit: j['unit'] as String,
      );
}

class QuotationStats {
  final int quotationsIssued;
  final int invoicesInPeriod;
  final double conversionRate;

  const QuotationStats({
    required this.quotationsIssued,
    required this.invoicesInPeriod,
    required this.conversionRate,
  });

  static const QuotationStats empty = QuotationStats(
    quotationsIssued: 0,
    invoicesInPeriod: 0,
    conversionRate: 0,
  );

  Map<String, dynamic> toJson() => {
        'quotationsIssued': quotationsIssued,
        'invoicesInPeriod': invoicesInPeriod,
        'conversionRate': conversionRate,
      };

  factory QuotationStats.fromJson(Map<String, dynamic> j) => QuotationStats(
        quotationsIssued: (j['quotationsIssued'] as num).toInt(),
        invoicesInPeriod: (j['invoicesInPeriod'] as num).toInt(),
        conversionRate: (j['conversionRate'] as num).toDouble(),
      );
}

class InvoiceStatusRow {
  final String id;
  final String date;
  final String? dueDate;
  final String customerName;
  final double total;
  final double paid;
  final double outstanding;
  final int daysOverdue;
  final bool hasNoDueDate;
  final String status;
  final bool isOverdue;

  const InvoiceStatusRow({
    required this.id,
    required this.date,
    this.dueDate,
    required this.customerName,
    required this.total,
    required this.paid,
    required this.outstanding,
    required this.daysOverdue,
    required this.hasNoDueDate,
    required this.status,
    required this.isOverdue,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'dueDate': dueDate,
        'customerName': customerName,
        'total': total,
        'paid': paid,
        'outstanding': outstanding,
        'daysOverdue': daysOverdue,
        'hasNoDueDate': hasNoDueDate,
        'status': status,
        'isOverdue': isOverdue,
      };

  factory InvoiceStatusRow.fromJson(Map<String, dynamic> j) => InvoiceStatusRow(
        id: j['id'] as String,
        date: j['date'] as String,
        dueDate: j['dueDate'] as String?,
        customerName: j['customerName'] as String,
        total: (j['total'] as num).toDouble(),
        paid: (j['paid'] as num).toDouble(),
        outstanding: (j['outstanding'] as num).toDouble(),
        daysOverdue: (j['daysOverdue'] as num).toInt(),
        hasNoDueDate: j['hasNoDueDate'] as bool,
        status: j['status'] as String,
        isOverdue: j['isOverdue'] as bool,
      );
}
