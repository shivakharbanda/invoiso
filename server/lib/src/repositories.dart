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
import 'package:invoiso_core/rpc/rpc_handlers.g.dart';

/// The SQL-backed repositories. Despite the `Sqlite` prefix they run on
/// whatever `DatabaseHelper.database` returns — on the server, the request's
/// company schema in Postgres (see CompanyStore.inCompany).
RpcRepositories serverRepositories() => RpcRepositories(
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
