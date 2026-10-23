import 'package:invoiso_core/models/spend_report_models.dart';

abstract class SpendReportRepository {
  Future<SpendTotals> getTotals(DateTime from, DateTime to);

  /// [groupBy]: `vendor` | `category` | `client` | `project` | `type`.
  Future<List<SpendGroupRow>> getSpendBy(
      String groupBy, DateTime from, DateTime to);
  Future<List<MonthlySpendPoint>> getMonthlySpend(DateTime from, DateTime to);
  Future<List<WalletBalance>> getWalletBalances();
  Future<List<ClientProfitRow>> getClientProfitability(
      DateTime from, DateTime to);
  Future<ProfitAndLoss> getProfitAndLoss(DateTime from, DateTime to);
  Future<List<InputTaxRow>> getInputTax(DateTime from, DateTime to);
}
