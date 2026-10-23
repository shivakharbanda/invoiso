import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/customer.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/supplier.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _inr0 = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

/// ₹1,23,456.78 (or whole rupees with [whole]).
String inr(double v, {bool whole = false}) => (whole ? _inr0 : _inr).format(v);

/// Amount in its billing currency: `USD 120.00`, `₹500.00`.
String money(double v, String currency) =>
    currency == 'INR' ? inr(v) : '$currency ${v.toStringAsFixed(2)}';

String entryTypeLabel(String type) => switch (type) {
      Expense.typeTopup => 'Wallet top-up',
      Expense.typeUsage => 'Usage',
      Expense.typeInvoice => 'Vendor invoice',
      Expense.typeSubscription => 'Subscription',
      _ => 'Other',
    };

String entryTypeHelp(String type) => switch (type) {
      Expense.typeTopup =>
        'Money added to a prepaid wallet (e.g. Neev "Add Funds", Vobiz recharge). Counts as cash out.',
      Expense.typeUsage =>
        'What you consumed from a prepaid wallet (GPU hours, call minutes). Counts as cost; no cash moves.',
      Expense.typeInvoice => 'A vendor bill you paid (e.g. AWS monthly invoice).',
      Expense.typeSubscription => 'A recurring fee (number rental, SaaS plan).',
      _ => 'Anything else you paid for.',
    };

Color entryTypeColor(BuildContext context, String type) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final c = switch (type) {
    Expense.typeTopup => Colors.indigo,
    Expense.typeUsage => Colors.teal,
    Expense.typeInvoice => Colors.deepOrange,
    Expense.typeSubscription => Colors.purple,
    _ => Colors.blueGrey,
  };
  return dark ? c.shade200 : c.shade700;
}

String taxKindLabel(String kind) => switch (kind) {
      'gst' => 'GST (CGST+SGST)',
      'igst' => 'IGST',
      'rcm' => 'Reverse charge (import)',
      _ => 'No tax',
    };

const paymentMethods = ['Bank transfer', 'UPI', 'Card', 'Cash', 'Wallet', 'Other'];
const usageUnits = ['GPU-hr', 'min', 'call', 'GB', 'request', 'unit'];

/// Everything the spend screens look things up in.
class SpendLookups {
  SpendLookups({
    required this.vendors,
    required this.categories,
    required this.projects,
    required this.customers,
  });

  final List<Supplier> vendors;
  final List<ExpenseCategory> categories;
  final List<Project> projects;
  final List<Customer> customers;

  static Future<SpendLookups> load(WidgetRef ref) async {
    final results = await Future.wait([
      ref.read(supplierRepositoryProvider).getAllSuppliers(),
      ref.read(expenseRepositoryProvider).getCategories(),
      ref.read(expenseRepositoryProvider).getProjects(includeArchived: true),
      ref.read(customerRepositoryProvider).getAllCustomers(),
    ]);
    final vendors = (results[0] as List<Supplier>)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final customers = (results[3] as List<Customer>)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return SpendLookups(
      vendors: vendors,
      categories: results[1] as List<ExpenseCategory>,
      projects: results[2] as List<Project>,
      customers: customers,
    );
  }

  String categoryName(String? id) =>
      categories.where((c) => c.id == id).firstOrNull?.name ?? '';

  String projectName(String? id) =>
      projects.where((p) => p.id == id).firstOrNull?.name ?? '';

  String customerName(String? id) =>
      customers.where((c) => c.id == id).firstOrNull?.name ?? '';

  Supplier? vendor(String? id) => vendors.where((v) => v.id == id).firstOrNull;
}

/// Small coloured label for an entry type.
class EntryTypeChip extends StatelessWidget {
  const EntryTypeChip(this.type, {super.key});

  final String type;

  @override
  Widget build(BuildContext context) {
    final color = entryTypeColor(context, type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(entryTypeLabel(type),
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Headline number card used across the spend tabs.
class SpendStatCard extends StatelessWidget {
  const SpendStatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.color,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color ?? theme.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(label,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700, color: color)),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(caption!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Date range presets for the spend screens.
class SpendPeriod {
  const SpendPeriod(this.label, this.from, this.to);

  final String label;
  final DateTime from;
  final DateTime to;

  static List<SpendPeriod> presets([DateTime? today]) {
    final now = today ?? DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final lastMonthStart = DateTime(now.year, now.month - 1);
    // Indian financial year: April–March.
    final fyStart = DateTime(now.month >= 4 ? now.year : now.year - 1, 4);
    return [
      SpendPeriod('This month', monthStart, DateTime(now.year, now.month + 1, 0)),
      SpendPeriod('Last month', lastMonthStart, DateTime(now.year, now.month, 0)),
      SpendPeriod('Last 90 days', now.subtract(const Duration(days: 89)), now),
      SpendPeriod('This FY (${fyStart.year}-${(fyStart.year + 1) % 100})', fyStart,
          DateTime(fyStart.year + 1, 3, 31)),
      SpendPeriod('Last FY (${fyStart.year - 1}-${fyStart.year % 100})',
          DateTime(fyStart.year - 1, 4), DateTime(fyStart.year, 3, 31)),
      SpendPeriod('All time', DateTime(2000), DateTime(now.year + 1, 12, 31)),
    ];
  }
}

/// Dropdown of [SpendPeriod.presets].
class SpendPeriodPicker extends StatelessWidget {
  const SpendPeriodPicker({super.key, required this.value, required this.onChanged});

  final SpendPeriod value;
  final ValueChanged<SpendPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final presets = SpendPeriod.presets();
    final selected = presets.indexWhere((p) => p.label == value.label);
    return DropdownButton<int>(
      value: selected < 0 ? 0 : selected,
      underline: const SizedBox.shrink(),
      items: [
        for (var i = 0; i < presets.length; i++)
          DropdownMenuItem(value: i, child: Text(presets[i].label)),
      ],
      onChanged: (i) => onChanged(presets[i!]),
    );
  }
}

String shortDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
