import 'package:invoiso_core/database/spend_report_service.dart';
import 'package:invoiso_core/models/spend_report_models.dart';
import 'package:invoiso_core/repositories/spend_report_repository.dart';

class SqliteSpendReportRepository implements SpendReportRepository {
  @override
  Future<SpendTotals> getTotals(DateTime from, DateTime to) =>
      SpendReportService.getTotals(from, to);

  @override
  Future<List<SpendGroupRow>> getSpendBy(
          String groupBy, DateTime from, DateTime to) =>
      SpendReportService.getSpendBy(groupBy, from, to);

  @override
  Future<List<MonthlySpendPoint>> getMonthlySpend(DateTime from, DateTime to) =>
      SpendReportService.getMonthlySpend(from, to);

  @override
  Future<List<WalletBalance>> getWalletBalances() =>
      SpendReportService.getWalletBalances();

  @override
  Future<List<ClientProfitRow>> getClientProfitability(
          DateTime from, DateTime to) =>
      SpendReportService.getClientProfitability(from, to);

  @override
  Future<ProfitAndLoss> getProfitAndLoss(DateTime from, DateTime to) =>
      SpendReportService.getProfitAndLoss(from, to);

  @override
  Future<List<InputTaxRow>> getInputTax(DateTime from, DateTime to) =>
      SpendReportService.getInputTax(from, to);
}
