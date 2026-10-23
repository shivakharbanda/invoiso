// Runs one business scenario three ways — SQLite, Postgres directly, and
// Postgres through the generated RPC layer (client → JSON → server handlers)
// — and compares every read the app makes. Any gap in the SQL translation or
// in a JSON codec shows up as a diff here.
//
// Needs a Postgres reachable at INVOISO_TEST_PG (default: the docker-compose
// dev container on 127.0.0.1:55432). Skips when it isn't reachable.
import 'dart:convert';
import 'dart:io';

import 'package:invoiso_core/database/database_helper.dart';
import 'package:invoiso_core/models/customer.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/invoice.dart';
import 'package:invoiso_core/models/invoice_item.dart';
import 'package:invoiso_core/models/product.dart';
import 'package:invoiso_core/models/purchase_bill.dart';
import 'package:invoiso_core/models/purchase_bill_item.dart';
import 'package:invoiso_core/models/supplier.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_auth_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_cash_ledger_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_company_info_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_customer_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_expense_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_invoice_item_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_invoice_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_payment_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_product_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_purchase_bill_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_report_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_settings_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_spend_report_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_supplier_payment_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_supplier_repository.dart';
import 'package:invoiso_core/rpc/http_repositories.g.dart';
import 'package:invoiso_core/rpc/rpc_client.dart';
import 'package:invoiso_core/rpc/rpc_handlers.g.dart';
import 'package:invoiso_pg/invoiso_pg.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

final _pgUrl = Platform.environment['INVOISO_TEST_PG'] ??
    'postgresql://postgres:invoiso@127.0.0.1:55432/invoiso?sslmode=disable';

/// The direct (SQL-backed) repositories.
RpcRepositories _direct() => RpcRepositories(
      auth: SqliteAuthRepository(),
      cashLedger: SqliteCashLedgerRepository(),
      companyInfo: SqliteCompanyInfoRepository(),
      customer: SqliteCustomerRepository(),
      expense: SqliteExpenseRepository(),
      invoiceItem: SqliteInvoiceItemRepository(),
      invoice: SqliteInvoiceRepository(),
      payment: SqlitePaymentRepository(),
      product: SqliteProductRepository(),
      purchaseBill: SqlitePurchaseBillRepository(),
      report: SqliteReportRepository(),
      settings: SqliteSettingsRepository(),
      spendReport: SqliteSpendReportRepository(),
      supplierPayment: SqliteSupplierPaymentRepository(),
      supplier: SqliteSupplierRepository(),
    );

/// Same wire format as the server: args and results go through jsonEncode,
/// so every codec in the generated layer is exercised.
class _LoopbackRpc implements RpcClient {
  _LoopbackRpc(this._handlers);

  final Map<String, RpcHandler> _handlers;

  @override
  Future<Object?> call(String method, Map<String, Object?> args) async {
    final decodedArgs = jsonDecode(jsonEncode(args)) as Map<String, dynamic>;
    final result = await _handlers[method]!(decodedArgs);
    return jsonDecode(jsonEncode(result));
  }
}

/// The generated HTTP clients, talking to the generated handlers in-process.
RpcRepositories _overRpc() {
  final rpc = _LoopbackRpc(rpcHandlers(_direct()));
  return RpcRepositories(
    auth: HttpAuthRepository(rpc),
    cashLedger: HttpCashLedgerRepository(rpc),
    companyInfo: HttpCompanyInfoRepository(rpc),
    customer: HttpCustomerRepository(rpc),
    expense: HttpExpenseRepository(rpc),
    invoiceItem: HttpInvoiceItemRepository(rpc),
    invoice: HttpInvoiceRepository(rpc),
    payment: HttpPaymentRepository(rpc),
    product: HttpProductRepository(rpc),
    purchaseBill: HttpPurchaseBillRepository(rpc),
    report: HttpReportRepository(rpc),
    settings: HttpSettingsRepository(rpc),
    spendReport: HttpSpendReportRepository(rpc),
    supplierPayment: HttpSupplierPaymentRepository(rpc),
    supplier: HttpSupplierRepository(rpc),
  );
}

final _p1 = Product(
    id: 'p1', name: 'GPU hour', description: 'A100', price: 250, stock: 100,
    hsncode: '998315', tax_rate: 18, purchasePrice: 180);
final _p2 = Product(
    id: 'p2', name: 'Call minutes', description: '', price: 1.2, stock: 0,
    hsncode: '998413', tax_rate: 18, type: 'service', unlimitedStock: true);
final _p3 = Product(
    id: 'p3', name: 'widget', description: '', price: 100, stock: 5,
    hsncode: '', tax_rate: 0, purchasePrice: 60);

Customer _customer(String id, String name) => Customer(
    id: id, name: name, email: '$id@example.com', phone: '9$id', address: '',
    gstin: '');

Future<void> _scenario(RpcRepositories r) async {
  for (final p in [_p1, _p2, _p3]) {
    await r.product.insertProduct(p);
  }
  final acme = _customer('c1', 'Acme');
  final beta = _customer('c2', 'beta corp');
  await r.customer.insertCustomer(acme);
  await r.customer.insertCustomer(beta);

  final invoices = [
    Invoice(
        id: '00000001', invoiceNumber: '00000001', customer: acme,
        type: 'Invoice', date: DateTime(2026, 2, 10),
        dueDate: DateTime(2026, 3, 10), taxRate: 0.18,
        items: [
          InvoiceItem(id: 'i1a', product: _p1, quantity: 10),
          InvoiceItem(id: 'i1b', product: _p3, quantity: 2, discount: 10),
        ]),
    Invoice(
        id: '00000002', invoiceNumber: '00000002', customer: beta,
        type: 'Invoice', date: DateTime(2026, 3, 5),
        items: [InvoiceItem(id: 'i2a', product: _p2, quantity: 1000)]),
    Invoice(
        id: '00000003', invoiceNumber: 'INV-3', customer: acme,
        type: 'Invoice', date: DateTime(2026, 3, 6),
        items: [InvoiceItem(id: 'i3a', product: _p3, quantity: 1)]),
    Invoice(
        id: '00000004', invoiceNumber: '00000001', customer: beta,
        type: 'Quotation', date: DateTime(2026, 3, 7),
        items: [InvoiceItem(id: 'q1a', product: _p1, quantity: 4)]),
  ];
  for (final i in invoices) {
    await r.invoice.insertInvoice(i);
  }
  await r.payment.addPayment(
      invoice: (await r.invoice.getInvoiceById('00000001'))!,
      amountPaid: 1000, datePaid: DateTime(2026, 2, 20), paymentMethod: 'UPI');
  final inv2 = (await r.invoice.getInvoiceById('00000002'))!;
  await r.payment.addPayment(
      invoice: inv2, amountPaid: inv2.total,
      datePaid: DateTime(2026, 3, 6), paymentMethod: 'Cash');
  await r.invoice.declineInvoice('00000003');

  await r.supplier.insertSupplier(
      Supplier(id: 's1', name: 'Neev Cloud', gstin: '27AAAAA0000A1Z5'));
  await r.purchaseBill.insertPurchaseBill(PurchaseBill(
      id: 'b1', supplierId: 's1', supplierName: 'Neev Cloud',
      billNumber: 'NC-77', billDate: DateTime(2026, 2, 1),
      items: [
        PurchaseBillItem(
            id: 'b1a', productId: 'p3', productName: 'widget', quantity: 10,
            costPerUnit: 55, taxRate: 18),
      ]));
  await r.supplierPayment.addPayment(
      bill: (await r.purchaseBill.getPurchaseBillById('b1'))!,
      amountPaid: 300, datePaid: DateTime(2026, 2, 15));

  await r.cashLedger
      .saveOpening(cash: 1000, upiBank: 5000, date: DateTime(2026, 1, 1));
  await r.cashLedger.addExchange(
      upiToCash: true, amount: 500, fee: 10, feeMethod: 'cash',
      dateTime: DateTime(2026, 2, 11, 10));
  await r.cashLedger.addMovement(
      type: 'expense', amount: 200, dateTime: DateTime(2026, 2, 12, 9),
      notes: 'Vobiz top-up');

  // ── Vendor spend ──
  await r.supplier.insertSupplier(Supplier(
      id: 'v-neev', name: 'Neev Cloud', gstin: '23AABCN1234Q1Z5',
      billingModel: 'prepaid', defaultCurrency: 'INR',
      defaultCategoryId: 'cat-gpu', lowBalanceThreshold: 5000));
  await r.supplier.insertSupplier(Supplier(
      id: 'v-vobiz', name: 'Vobiz', billingModel: 'prepaid',
      defaultCurrency: 'INR', lowBalanceThreshold: 100));
  await r.supplier.insertSupplier(
      Supplier(id: 'v-aws', name: 'AWS', billingModel: 'postpaid',
          defaultCurrency: 'USD'));
  final categories = await r.expense.getCategories(); // seeds defaults
  await r.expense.saveProject(
      const Project(id: 'pr1', name: 'Acme voice bot', customerId: 'c1'));
  Expense e(String id, String vendorId, String vendor, String type,
          DateTime date, double amount,
          {double tax = 0, String taxKind = 'none', double? inr,
          String currency = 'INR', String? customer, String? project,
          double? qty, String? unit, String? category}) =>
      Expense(
          id: id, vendorId: vendorId, vendorName: vendor, entryType: type,
          date: date, amount: amount, taxAmount: tax, taxKind: taxKind,
          inrAmount: inr ?? amount + tax, currencyCode: currency,
          customerId: customer, projectId: project, usageQty: qty,
          usageUnit: unit, categoryId: category ?? categories.first.id,
          description: '$vendor $type');
  for (final x in [
    e('x1', 'v-neev', 'Neev Cloud', 'topup', DateTime(2026, 2, 1), 20000,
        tax: 3600, taxKind: 'gst'),
    e('x2', 'v-neev', 'Neev Cloud', 'usage', DateTime(2026, 2, 15), 12000,
        customer: 'c1', project: 'pr1', qty: 80, unit: 'GPU-hr'),
    e('x3', 'v-vobiz', 'Vobiz', 'topup', DateTime(2026, 2, 3), 5000,
        tax: 900, taxKind: 'igst', category: 'cat-telephony'),
    e('x4', 'v-vobiz', 'Vobiz', 'usage', DateTime(2026, 3, 2), 4950,
        customer: 'c2', qty: 4125, unit: 'min', category: 'cat-telephony'),
    e('x5', 'v-aws', 'AWS', 'invoice', DateTime(2026, 3, 3), 120,
        tax: 21.6, taxKind: 'rcm', inr: 12150.5, currency: 'USD',
        category: 'cat-cloud'),
  ]) {
    await r.expense.saveExpense(x);
  }
  await r.expense.saveExpense(e('x6', 'v-aws', 'AWS', 'other',
      DateTime(2026, 3, 9), 1, inr: 90)); // then deleted
  await r.expense.deleteExpense('x6');
  await r.expense.addAttachment('x5', 'aws-march.pdf', 'application/pdf',
      base64Encode(utf8.encode('%PDF-1.4 fake receipt')));
  await r.expense.saveRecurring(RecurringExpense(
      id: 'rc1', vendorId: 'v-vobiz', vendorName: 'Vobiz',
      description: 'Number rental', amount: 500, taxAmount: 90,
      taxKind: 'gst', inrAmount: 590, nextDue: DateTime(2026, 1, 31)));
  final due = await r.expense.getDueRecurring(DateTime(2026, 2, 28));
  await r.expense.recordRecurring(
      due.single.id,
      e('x7', 'v-vobiz', 'Vobiz', 'subscription', DateTime(2026, 1, 31), 500,
          tax: 90, taxKind: 'gst'));
}

/// Every read, rendered to comparable JSON. Generated ids/timestamps are
/// masked since they legitimately differ between runs.
Future<Map<String, Object?>> _snapshot(RpcRepositories r) async {
  final inv = r.invoice, rep = r.report, cus = r.customer, prod = r.product;
  final pb = r.purchaseBill, sup = r.supplier, cash = r.cashLedger;
  final pay = r.payment, settings = r.settings;
  final from = DateTime(2026, 1, 1), to = DateTime(2026, 12, 31);
  final reads = <String, Future<Object?> Function()>{
    'invoice.byId': () async => [
          for (final id in ['00000001', '00000002', '00000003', '00000004'])
            await inv.getInvoiceById(id)
        ],
    'invoice.all': inv.getAllInvoices,
    'invoice.page': () => inv.getInvoicesPaginated(),
    'invoice.pageSearch': () => inv.getInvoicesPaginated(searchQuery: 'ACME'),
    'invoice.count': () => inv.getInvoiceCount(),
    'invoice.export': () => inv.getInvoicesForExport(fromId: 1, toId: 3),
    'invoice.nextId': inv.peekNextId,
    'invoice.nextNo': () => inv.peekNextInvoiceNumber('Invoice'),
    'invoice.dashboard': inv.getDashboardFinancials,
    'invoice.recent': () => inv.getRecentInvoices(),
    'invoice.overdue': () => inv.getOverdueInvoices(),
    'invoice.openFor': () => inv.getOpenInvoicesForCustomer('c1'),
    'invoice.withInvoices': () => inv.getCustomersWithInvoices(),
    'invoice.monthly': inv.getMonthlyRevenue,
    'invoice.topCustomers': inv.getTopCustomers,
    'invoice.topProducts': inv.getTopProducts,
    'invoice.prevBalance': () => inv.getPreviousBalanceDueForCustomer(
        customerId: 'c1', currencyCode: 'INR', asOfDate: DateTime(2026, 4, 1)),
    'report.revenue': () => rep.getRevenueSummary(from, to),
    'report.monthly': () => rep.getMonthlyRevenueTrend(from, to),
    'report.daily': () => rep.getDailyRevenueTrend(from, to),
    'report.status': () => rep.getPaymentStatusBreakdown(from, to),
    'report.aged': () => rep.getAgedReceivables(),
    'report.agedSummary': () => rep.getAgedReceivableSummary(),
    'report.outstanding': () => rep.getOutstandingByCustomer(),
    'report.currencies': rep.getInvoiceCurrencies,
    'report.tax': () => rep.getTaxByRate(from, to),
    'report.topCustomers': () => rep.getTopCustomers(from, to),
    'report.stmtCustomers': () => rep.getStatementCustomers(),
    'report.topProducts': () => rep.getTopProducts(from, to),
    'report.topProductsProfit': () =>
        rep.getTopProducts(from, to, rankByProfit: true),
    'report.quotations': () => rep.getQuotationStats(from, to),
    'report.statusList': () => rep.getInvoiceStatusList(from, to),
    'report.missingCost': () => rep.getMissingCostItemCount(from, to),
    'report.inventory': rep.getInventoryValuationSummary,
    'report.inventoryRows': () => rep.getInventoryValuationRows(),
    'customer.all': cus.getAllCustomers,
    'customer.stats': cus.getCustomerListStats,
    'customer.ids': () => cus.getCustomerListIds(query: 'A'),
    'customer.idsSorted': () => cus.getCustomerListIds(orderBy: 'name'),
    'customer.dupe': () => cus.findDuplicate('c2@example.com', ''),
    'product.all': prod.getAllProducts,
    'product.search': () => prod.searchProducts('GPU'),
    'product.searchCase': () => prod.searchProducts('gpu'),
    'product.stats': prod.getProductListStats,
    'product.low': prod.getLowStockProducts,
    'product.out': prod.getOutOfStockProducts,
    'purchase.all': pb.getAllPurchaseBills,
    'purchase.page': () => pb.getPurchaseBillsPaginated(searchQuery: 'neev'),
    'supplier.all': sup.getAllSuppliers,
    'supplier.outstanding': () => sup.getOutstandingBalance('s1'),
    'cash.entries': () => cash.getEntries(),
    'cash.balances': () => cash.getBalances(),
    'cash.period': () => cash.getPeriodTotals(from, to),
    'cash.daily': () => cash.getDailyNet(from, to),
    'payments.between': () => pay.getAllPaymentsBetween(from, to),
    'payments.tax': () => pay.getTaxPaidBetween(from, to),
    'settings.currency': () async => (await settings.getCurrency()).code,
    'settings.dateFormat': () async => (await settings.getDateFormat()).name,
    'spend.expenses': () => r.expense.getExpenses(const ExpenseFilter()),
    'spend.filtered': () => r.expense.getExpenses(ExpenseFilter(
        from: DateTime(2026, 2, 1), to: DateTime(2026, 2, 28),
        vendorId: 'v-neev', search: 'neev')),
    'spend.count': () => r.expense.countExpenses(const ExpenseFilter()),
    'spend.one': () => r.expense.getExpense('x5'),
    'spend.categories': r.expense.getCategories,
    'spend.projects': () => r.expense.getProjects(),
    'spend.recurring': r.expense.getRecurring,
    'spend.attachments': () => r.expense.getAttachments('x5'),
    'spend.attachmentData': () async {
      final list = await r.expense.getAttachments('x5');
      return r.expense.getAttachmentData(list.single.id);
    },
    'spend.suppliers': sup.getAllSuppliers,
    'spendReport.totals': () => r.spendReport.getTotals(from, to),
    for (final g in ['vendor', 'category', 'client', 'project', 'type'])
      'spendReport.by.$g': () => r.spendReport.getSpendBy(g, from, to),
    'spendReport.monthly': () => r.spendReport.getMonthlySpend(from, to),
    'spendReport.wallets': r.spendReport.getWalletBalances,
    'spendReport.clients': () =>
        r.spendReport.getClientProfitability(from, to),
    'spendReport.pnl': () => r.spendReport.getProfitAndLoss(from, to),
    'spendReport.itc': () => r.spendReport.getInputTax(from, to),
  };
  final out = <String, Object?>{};
  for (final e in reads.entries) {
    try {
      out[e.key] = _mask(jsonEncode(_plain(await e.value())));
    } catch (err) {
      out[e.key] = 'THREW: $err';
    }
  }
  return out;
}

/// JSON-ready form of a read result (models via toJson/toMap, records via
/// their structural toString).
Object? _plain(Object? v) {
  if (v == null || v is num || v is String || v is bool) return v;
  if (v is List) return v.map(_plain).toList();
  if (v is Map) return v.map((k, e) => MapEntry('$k', _plain(e)));
  final dynamic d = v;
  try {
    return _plain(d.toJson());
  } on NoSuchMethodError {
    try {
      return _plain(d.toMap());
    } on NoSuchMethodError {
      return v.toString();
    }
  }
}

final _uuid =
    RegExp(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}');

String _mask(String s) {
  final today = DateTime.now().toIso8601String().substring(0, 10);
  return s
      .replaceAll(_uuid, '<uuid>')
      .replaceAll(RegExp('$today[T ][0-9:.]+Z?'), '<now>');
}

void main() {
  late pg.Connection conn;
  var pgAvailable = true;
  final schemaBase = 'company_parity_${DateTime.now().millisecondsSinceEpoch}';
  final schemas = <String>[];

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    try {
      conn = await pg.Connection.openFromUrl(_pgUrl);
    } catch (_) {
      pgAvailable = false;
    }
  });

  tearDownAll(() async {
    DatabaseHelper.databaseOverride = null;
    if (pgAvailable) {
      for (final schema in schemas) {
        await conn.execute('DROP SCHEMA IF EXISTS "$schema" CASCADE');
      }
      await conn.close();
    }
  });

  test('identical results on SQLite, Postgres, and Postgres over RPC',
      () async {
    if (!pgAvailable) {
      markTestSkipped('Postgres not reachable at $_pgUrl');
      return;
    }
    // 1. SQLite (fresh file, seeded by _createDB).
    final tmp = Directory.systemTemp.createTempSync('invoiso_parity');
    DatabaseHelper.dataDirectoryProvider = () async => tmp.path;
    await DatabaseHelper().switchToFile('parity.db');
    await _scenario(_direct());
    final onSqlite = await _snapshot(_direct());
    await DatabaseHelper().close();
    tmp.deleteSync(recursive: true);

    // 2. Postgres directly, 3. Postgres through the generated RPC layer —
    // each in its own fresh schema seeded from the same _createDB.
    final sync = await SchemaSync.load();
    Future<Map<String, Object?>> onPg(String schema, RpcRepositories r) async {
      schemas.add(schema);
      await sync.createCompany(conn, schema);
      final db = await PgDatabase.open(conn, sync.catalog, schema);
      DatabaseHelper.databaseOverride = () async => db;
      await _scenario(r);
      return _snapshot(r);
    }

    final direct = await onPg('${schemaBase}_direct', _direct());
    final viaRpc = await onPg('${schemaBase}_rpc', _overRpc());

    expect(onSqlite.values.where((v) => '$v'.startsWith('THREW')), isEmpty,
        reason: 'reads failing on SQLite itself');
    for (final (name, other) in [('pg', direct), ('pg+rpc', viaRpc)]) {
      final diffs = [
        for (final k in onSqlite.keys)
          if (onSqlite[k] != other[k])
            '$k\n  sqlite: ${onSqlite[k]}\n  $name: ${other[k]}',
      ];
      expect(diffs, isEmpty, reason: diffs.join('\n\n'));
    }
  });
}
