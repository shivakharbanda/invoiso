// Spend tracker arithmetic on SQLite: wallets, cash vs. cost, input tax,
// client profitability, recurring templates. (parity_test.dart proves the
// same numbers come back from Postgres and over RPC.)
import 'dart:io';

import 'package:invoiso_core/database/database_helper.dart';
import 'package:invoiso_core/models/customer.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/supplier.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_customer_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_expense_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_spend_report_repository.dart';
import 'package:invoiso_core/repositories/sqlite/sqlite_supplier_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  final expenses = SqliteExpenseRepository();
  final reports = SqliteSpendReportRepository();
  final from = DateTime(2026, 1, 1), to = DateTime(2026, 12, 31);

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('invoiso_spend');
    DatabaseHelper.dataDirectoryProvider = () async => tmp.path;
    await DatabaseHelper().switchToFile('spend.db');

    final suppliers = SqliteSupplierRepository();
    await suppliers.insertSupplier(Supplier(
        id: 'neev', name: 'Neev Cloud', billingModel: 'prepaid',
        defaultCurrency: 'INR', lowBalanceThreshold: 5000));
    await suppliers.insertSupplier(Supplier(
        id: 'vobiz', name: 'Vobiz', billingModel: 'prepaid',
        lowBalanceThreshold: 100));
    await suppliers.insertSupplier(
        Supplier(id: 'aws', name: 'AWS', billingModel: 'postpaid'));
    await SqliteCustomerRepository().insertCustomer(Customer(
        id: 'c1', name: 'Acme', email: '', phone: '', address: '', gstin: ''));

    Future<void> add(String id, String vendor, String type, double amount,
        {double tax = 0, String kind = 'none', double? inr,
        String currency = 'INR', String? customer, int month = 2}) {
      return expenses.saveExpense(Expense(
          id: id, vendorId: vendor, vendorName: vendor, entryType: type,
          date: DateTime(2026, month, 10), amount: amount, taxAmount: tax,
          taxKind: kind, inrAmount: inr ?? amount + tax,
          currencyCode: currency, customerId: customer));
    }

    await add('t1', 'neev', 'topup', 20000, tax: 3600, kind: 'gst');
    await add('u1', 'neev', 'usage', 12000, customer: 'c1');
    await add('t2', 'vobiz', 'topup', 5000, tax: 900, kind: 'igst');
    await add('u2', 'vobiz', 'usage', 4950, customer: 'c1', month: 3);
    // USD invoice: $120 + $21.60 reverse-charge GST, bank debited ₹12,150.50.
    await add('a1', 'aws', 'invoice', 120,
        tax: 21.6, kind: 'rcm', inr: 12150.5, currency: 'USD', month: 3);
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
    tmp.deleteSync(recursive: true);
  });

  test('wallet = top-ups minus usage, low when under threshold', () async {
    final wallets = {for (final w in await reports.getWalletBalances()) w.vendorId: w};
    expect(wallets.keys, unorderedEquals(['neev', 'vobiz'])); // AWS: postpaid
    expect(wallets['neev']!.balance, 8000);
    expect(wallets['neev']!.isLow, isFalse);
    expect(wallets['vobiz']!.balance, 50);
    expect(wallets['vobiz']!.isLow, isTrue);
  });

  test('cash out counts top-ups, cost counts usage; invoices count in both',
      () async {
    final t = await reports.getTotals(from, to);
    expect(t.cashOut, 23600 + 5900 + 12150.5);
    expect(t.cost, 12000 + 4950 + 12150.5);
    // RCM tax on the USD invoice converted at the implied rate.
    expect(t.inputTax, closeTo(3600 + 900 + 12150.5 * 21.6 / 141.6, 1e-6));
    expect(t.entryCount, 5);
  });

  test('client profitability takes tagged vendor cost', () async {
    final rows = await reports.getClientProfitability(from, to);
    final acme = rows.singleWhere((r) => r.customerKey == 'c1');
    expect(acme.customerName, 'Acme');
    expect(acme.vendorCost, 12000 + 4950);
    expect(acme.profit, -(12000 + 4950)); // no invoices yet
  });

  test('monthly spend has every month in range', () async {
    final months = await reports.getMonthlySpend(
        DateTime(2026, 1, 1), DateTime(2026, 4, 30));
    expect(months.map((m) => m.month), ['2026-01', '2026-02', '2026-03', '2026-04']);
    expect(months[1].cashOut, 23600 + 5900);
    expect(months[2].cost, 4950 + 12150.5);
  });

  test('deleted expenses drop out of lists and reports', () async {
    await expenses.saveExpense(Expense(
        id: 'gone', vendorName: 'x', entryType: 'other',
        date: DateTime(2026, 2, 1), amount: 999, inrAmount: 999));
    await expenses.deleteExpense('gone');
    expect((await expenses.getExpenses(const ExpenseFilter())).map((e) => e.id),
        isNot(contains('gone')));
    expect((await reports.getTotals(from, to)).entryCount, 5);
  });

  test('recurring: due list, record advances month-end safely', () async {
    await expenses.saveRecurring(RecurringExpense(
        id: 'r1', vendorName: 'Vobiz', amount: 500, inrAmount: 590,
        nextDue: DateTime(2026, 1, 31)));
    expect(await expenses.getDueRecurring(DateTime(2026, 1, 30)), isEmpty);
    final due = await expenses.getDueRecurring(DateTime(2026, 2, 1));
    expect(due.single.id, 'r1');
    await expenses.recordRecurring('r1', Expense(
        id: 'r1-jan', vendorName: 'Vobiz', entryType: 'subscription',
        date: DateTime(2026, 1, 31), amount: 500, inrAmount: 590));
    final r = (await expenses.getRecurring()).single;
    expect(r.nextDue, DateTime(2026, 2, 28));
    expect((await expenses.getExpense('r1-jan'))!.recurringId, 'r1');
  });

  test('categories seed once', () async {
    final first = await expenses.getCategories();
    expect(first.map((c) => c.id), contains('cat-gpu'));
    await expenses.deleteCategory('cat-other');
    final second = await expenses.getCategories();
    expect(second.length, first.length - 1);
  });
}
