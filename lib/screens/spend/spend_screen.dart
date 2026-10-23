import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/spend_report_models.dart';
import 'package:invoiso_core/models/user.dart';

import 'expense_form_dialog.dart';
import 'spend_common.dart';
import 'spend_recurring_tab.dart';
import 'spend_reports_tab.dart';
import 'spend_setup_tab.dart';
import 'spend_wallets_tab.dart';

/// Vendor spend: GPU cloud, telephony, SaaS… — everything entered by hand.
class SpendScreen extends ConsumerStatefulWidget {
  const SpendScreen({super.key, required this.user});

  final User user;

  @override
  ConsumerState<SpendScreen> createState() => _SpendScreenState();
}

class _SpendScreenState extends ConsumerState<SpendScreen>
    with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 5, vsync: this);
  SpendLookups? _lookups;
  Object? _error;

  /// Bumped after any change so every tab reloads.
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _reloadLookups();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reloadLookups() async {
    try {
      final l = await SpendLookups.load(ref);
      if (mounted) setState(() {
        _lookups = l;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _changed() {
    _reloadLookups();
    setState(() => _revision++);
  }

  Future<void> _newExpense({Expense? template, String? title}) async {
    final saved = await showExpenseForm(context,
        lookups: _lookups!, initial: template, title: title,
        createdBy: widget.user.id);
    if (saved) _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l = _lookups;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Spend'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Entries'),
            Tab(icon: Icon(Icons.account_balance_wallet_outlined), text: 'Wallets'),
            Tab(icon: Icon(Icons.event_repeat_outlined), text: 'Recurring'),
            Tab(icon: Icon(Icons.insights_outlined), text: 'Reports'),
            Tab(icon: Icon(Icons.tune), text: 'Vendors & setup'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: l == null ? null : () => _newExpense(),
              icon: const Icon(Icons.add),
              label: const Text('New expense'),
            ),
          ),
        ],
      ),
      body: _error != null
          ? Center(child: Text('Could not load: $_error'))
          : l == null
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _EntriesTab(
                        key: ValueKey('entries$_revision'),
                        lookups: l,
                        user: widget.user,
                        onChanged: _changed),
                    SpendWalletsTab(
                        key: ValueKey('wallets$_revision'),
                        lookups: l,
                        onNewEntry: (t, title) => _newExpense(template: t, title: title)),
                    SpendRecurringTab(
                        key: ValueKey('recurring$_revision'),
                        lookups: l,
                        user: widget.user,
                        onChanged: _changed),
                    SpendReportsTab(key: ValueKey('reports$_revision'), lookups: l),
                    SpendSetupTab(lookups: l, onChanged: _changed),
                  ],
                ),
    );
  }
}

class _EntriesTab extends ConsumerStatefulWidget {
  const _EntriesTab({
    super.key,
    required this.lookups,
    required this.user,
    required this.onChanged,
  });

  final SpendLookups lookups;
  final User user;
  final VoidCallback onChanged;

  @override
  ConsumerState<_EntriesTab> createState() => _EntriesTabState();
}

class _EntriesTabState extends ConsumerState<_EntriesTab> {
  SpendPeriod _period = SpendPeriod.presets().first;
  String? _vendorId;
  String? _type;
  String? _customerId;
  final _search = TextEditingController();

  SpendTotals? _totals;
  List<Expense> _entries = [];
  List<RecurringExpense> _due = [];
  int _lowWallets = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final expenses = ref.read(expenseRepositoryProvider);
    final reports = ref.read(spendReportRepositoryProvider);
    final filter = ExpenseFilter(
      from: _period.from,
      to: _period.to,
      vendorId: _vendorId,
      entryType: _type,
      customerId: _customerId,
      search: _search.text,
    );
    final results = await Future.wait([
      reports.getTotals(_period.from, _period.to),
      expenses.getExpenses(filter, limit: 500),
      expenses.getDueRecurring(DateTime.now()),
      reports.getWalletBalances(),
    ]);
    if (!mounted) return;
    setState(() {
      _totals = results[0] as SpendTotals;
      _entries = results[1] as List<Expense>;
      _due = results[2] as List<RecurringExpense>;
      _lowWallets = (results[3] as List<WalletBalance>).where((w) => w.isLow).length;
      _loading = false;
    });
  }

  Future<void> _edit(Expense e) async {
    final saved = await showExpenseForm(context,
        lookups: widget.lookups, initial: e, isNew: false);
    if (saved) widget.onChanged();
  }

  Future<void> _duplicate(Expense e) async {
    final saved = await showExpenseForm(context,
        lookups: widget.lookups,
        initial: Expense.fromMap({...e.toMap(), 'date': DateTime.now().toIso8601String()}),
        title: 'Duplicate expense',
        createdBy: widget.user.id);
    if (saved) widget.onChanged();
  }

  Future<void> _delete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('${e.vendorName} · ${shortDate(e.date)} · ${inr(e.inrAmount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(expenseRepositoryProvider).deleteExpense(e.id);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = widget.lookups;
    final t = _totals;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Text('Period:', style: theme.textTheme.titleSmall),
          const SizedBox(width: 8),
          SpendPeriodPicker(
              value: _period,
              onChanged: (p) {
                _period = p;
                _load();
              }),
          const SizedBox(width: 8),
          Text('${shortDate(_period.from)} – ${shortDate(_period.to)}',
              style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 12),
        if (t != null)
          LayoutBuilder(builder: (context, c) {
            final cards = [
              SpendStatCard(
                  label: 'Cash out',
                  value: inr(t.cashOut, whole: true),
                  caption: 'Top-ups, vendor invoices, subscriptions',
                  icon: Icons.north_east),
              SpendStatCard(
                  label: 'Cost consumed',
                  value: inr(t.cost, whole: true),
                  caption: 'Usage + invoices + subscriptions',
                  icon: Icons.local_fire_department_outlined),
              SpendStatCard(
                  label: 'Input tax (GST/IGST/RCM)',
                  value: inr(t.inputTax, whole: true),
                  caption: 'Claimable credit — confirm with your CA',
                  icon: Icons.account_balance_outlined),
              SpendStatCard(
                  label: 'Low wallets',
                  value: '$_lowWallets',
                  caption: _lowWallets == 0 ? 'All above their alert level' : 'See Wallets tab',
                  icon: Icons.warning_amber_rounded,
                  color: _lowWallets > 0 ? theme.colorScheme.error : null),
            ];
            final perRow = c.maxWidth > 1000 ? 4 : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  SizedBox(width: (c.maxWidth - 12 * (perRow - 1)) / perRow, child: card),
              ],
            );
          }),
        if (_due.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.event_repeat),
              title: Text('${_due.length} recurring '
                  '${_due.length == 1 ? 'expense is' : 'expenses are'} due'),
              subtitle: Text(_due.map((r) => r.description.isEmpty ? r.vendorName : r.description).join(', ')),
              trailing: const Text('Record them in the Recurring tab'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search vendor, description, ref…',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _load(),
              ),
            ),
            _filter<String?>('Vendor', _vendorId, {
              for (final v in l.vendors) v.id: v.name,
            }, (v) => _vendorId = v),
            _filter<String?>('Type', _type, {
              for (final t in Expense.types) t: entryTypeLabel(t),
            }, (v) => _type = v),
            _filter<String?>('Client', _customerId, {
              for (final c in l.customers) c.id: c.name,
            }, (v) => _customerId = v),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(children: [
              Icon(Icons.receipt_long_outlined, size: 48, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              const Text('No expenses in this period. Use "New expense" to add one.'),
            ]),
          )
        else
          Card(
            child: Column(children: [
              for (final e in _entries) ...[
                _ExpenseRow(
                  expense: e,
                  lookups: l,
                  onTap: () => _edit(e),
                  onDuplicate: () => _duplicate(e),
                  onDelete: () => _delete(e),
                ),
                if (e != _entries.last) const Divider(height: 1),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _filter<T>(String label, T value, Map<String, String> options,
      void Function(String?) set) {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String?>(
        value: options.containsKey(value) ? value as String? : null,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: label, isDense: true, border: const OutlineInputBorder()),
        items: [
          const DropdownMenuItem(value: null, child: Text('All')),
          for (final e in options.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          set(v);
          _load();
        },
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.expense,
    required this.lookups,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  final Expense expense;
  final SpendLookups lookups;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    final theme = Theme.of(context);
    final tags = [
      lookups.categoryName(e.categoryId),
      lookups.customerName(e.customerId),
      lookups.projectName(e.projectId),
      if (e.usageQty != null) '${e.usageQty!.toStringAsFixed(e.usageQty! % 1 == 0 ? 0 : 2)} ${e.usageUnit ?? ''}',
      if (e.referenceNo != null) '#${e.referenceNo}',
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          SizedBox(width: 90, child: Text(shortDate(e.date))),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(e.vendorName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  EntryTypeChip(e.entryType),
                  if (e.attachmentCount > 0) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.attach_file, size: 16, color: theme.colorScheme.outline),
                  ],
                ]),
                if (e.description.isNotEmpty || tags.isNotEmpty)
                  Text(
                    [e.description, tags].where((s) => s.isNotEmpty).join(' — '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(inr(e.inrAmount),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (e.currencyCode != 'INR')
                  Text(money(e.total, e.currencyCode), style: theme.textTheme.bodySmall)
                else if (e.taxAmount > 0)
                  Text('incl. ${inr(e.taxAmount)} ${e.taxKind.toUpperCase()}',
                      style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'dup' ? onDuplicate() : onDelete(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dup', child: Text('Duplicate')),
              PopupMenuItem(value: 'del', child: Text('Delete')),
            ],
          ),
        ]),
      ),
    );
  }
}
