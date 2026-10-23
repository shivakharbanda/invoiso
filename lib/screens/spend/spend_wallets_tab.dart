import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/spend_report_models.dart';
import 'package:uuid/uuid.dart';

import 'spend_common.dart';

/// Prepaid balances (Neev, Vobiz…): top-ups minus logged usage. Balances
/// are only as current as the entries you've made.
class SpendWalletsTab extends ConsumerStatefulWidget {
  const SpendWalletsTab({super.key, required this.lookups, required this.onNewEntry});

  final SpendLookups lookups;
  final void Function(Expense template, String title) onNewEntry;

  @override
  ConsumerState<SpendWalletsTab> createState() => _SpendWalletsTabState();
}

class _SpendWalletsTabState extends ConsumerState<SpendWalletsTab> {
  List<WalletBalance>? _wallets;

  @override
  void initState() {
    super.initState();
    ref.read(spendReportRepositoryProvider).getWalletBalances().then((w) {
      if (mounted) setState(() => _wallets = w);
    });
  }

  Expense _template(WalletBalance w, String type) {
    final v = widget.lookups.vendor(w.vendorId);
    return Expense(
      id: const Uuid().v4(),
      vendorId: w.vendorId,
      vendorName: w.vendorName,
      categoryId: v?.defaultCategoryId,
      entryType: type,
      date: DateTime.now(),
      currencyCode: w.currencyCode,
      amount: 0,
      inrAmount: 0,
      taxKind: type == Expense.typeTopup && w.currencyCode == 'INR' ? 'gst' : 'none',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wallets = _wallets;
    if (wallets == null) return const Center(child: CircularProgressIndicator());
    if (wallets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'No prepaid wallets yet. In "Vendors & setup", set a vendor\'s billing '
            'to Prepaid (e.g. Neev Cloud, Vobiz), then record top-ups and usage.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Balance = top-ups (credit before tax) − usage you\'ve logged. Log usage '
          'from the vendor dashboard regularly to keep this accurate.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final w in wallets)
              SizedBox(
                width: 360,
                child: Card(
                  shape: w.isLow
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.colorScheme.error, width: 1.5))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.account_balance_wallet_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(w.vendorName, style: theme.textTheme.titleMedium),
                          ),
                          if (w.isLow)
                            Chip(
                              label: const Text('Low'),
                              backgroundColor: theme.colorScheme.errorContainer,
                              visualDensity: VisualDensity.compact,
                            ),
                        ]),
                        const SizedBox(height: 12),
                        Text(money(w.balance, w.currencyCode),
                            style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: w.isLow ? theme.colorScheme.error : null)),
                        const SizedBox(height: 8),
                        Text('Topped up ${money(w.toppedUp, w.currencyCode)} · '
                            'used ${money(w.used, w.currencyCode)}'),
                        if (w.lowBalanceThreshold != null)
                          Text('Alert below ${money(w.lowBalanceThreshold!, w.currencyCode)}',
                              style: theme.textTheme.bodySmall),
                        if (w.lastTopupDate != null)
                          Text('Last top-up ${shortDate(DateTime.parse(w.lastTopupDate!))}',
                              style: theme.textTheme.bodySmall),
                        const SizedBox(height: 12),
                        Row(children: [
                          FilledButton.tonalIcon(
                            onPressed: () => widget.onNewEntry(
                                _template(w, Expense.typeTopup), 'Top up ${w.vendorName}'),
                            icon: const Icon(Icons.add_card, size: 18),
                            label: const Text('Top up'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => widget.onNewEntry(
                                _template(w, Expense.typeUsage), 'Log ${w.vendorName} usage'),
                            icon: const Icon(Icons.speed, size: 18),
                            label: const Text('Log usage'),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
