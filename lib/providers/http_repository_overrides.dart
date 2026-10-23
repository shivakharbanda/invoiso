import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso/services/server/app_server.dart';
import 'package:invoiso/services/server/server_auth_repository.dart';
import 'package:invoiso_core/rpc/http_repositories.g.dart';

/// Server mode: every repository is the generated HTTP client talking to the
/// invoiso server through [AppServer.rpc].
final httpRepositoryOverrides = <Override>[
  customerRepositoryProvider
      .overrideWith((ref) => HttpCustomerRepository(AppServer.rpc)),
  invoiceRepositoryProvider
      .overrideWith((ref) => HttpInvoiceRepository(AppServer.rpc)),
  productRepositoryProvider
      .overrideWith((ref) => HttpProductRepository(AppServer.rpc)),
  paymentRepositoryProvider
      .overrideWith((ref) => HttpPaymentRepository(AppServer.rpc)),
  cashLedgerRepositoryProvider
      .overrideWith((ref) => HttpCashLedgerRepository(AppServer.rpc)),
  companyInfoRepositoryProvider
      .overrideWith((ref) => HttpCompanyInfoRepository(AppServer.rpc)),
  settingsRepositoryProvider
      .overrideWith((ref) => HttpSettingsRepository(AppServer.rpc)),
  reportRepositoryProvider
      .overrideWith((ref) => HttpReportRepository(AppServer.rpc)),
  invoiceItemRepositoryProvider
      .overrideWith((ref) => HttpInvoiceItemRepository(AppServer.rpc)),
  authRepositoryProvider.overrideWith((ref) => ServerAuthRepository()),
  supplierRepositoryProvider
      .overrideWith((ref) => HttpSupplierRepository(AppServer.rpc)),
  purchaseBillRepositoryProvider
      .overrideWith((ref) => HttpPurchaseBillRepository(AppServer.rpc)),
  supplierPaymentRepositoryProvider
      .overrideWith((ref) => HttpSupplierPaymentRepository(AppServer.rpc)),
  expenseRepositoryProvider
      .overrideWith((ref) => HttpExpenseRepository(AppServer.rpc)),
  spendReportRepositoryProvider
      .overrideWith((ref) => HttpSpendReportRepository(AppServer.rpc)),
];
