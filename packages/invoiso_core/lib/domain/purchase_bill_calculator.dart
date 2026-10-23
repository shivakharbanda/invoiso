import 'package:invoiso_core/common/common.dart';
import 'package:invoiso_core/domain/invoice_calculator.dart';

class PurchaseBillCalculator {
  const PurchaseBillCalculator._();

  static double outstanding({
    required double total,
    required double paid,
  }) {
    final balance = total - paid;
    return balance <= InvoiceCalculator.moneyEpsilon ? 0.0 : balance;
  }

  static bool isPaid({
    required double total,
    required double paid,
  }) =>
      outstanding(total: total, paid: paid) <= InvoiceCalculator.moneyEpsilon;

  static PaymentStatus paymentStatus({
    required double total,
    required double paid,
  }) {
    if (paid <= InvoiceCalculator.moneyEpsilon) return PaymentStatus.unpaid;
    return isPaid(total: total, paid: paid)
        ? PaymentStatus.paid
        : PaymentStatus.partial;
  }
}
