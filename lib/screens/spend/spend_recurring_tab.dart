import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/user.dart';
import 'package:uuid/uuid.dart';

import 'expense_form_dialog.dart';
import 'spend_common.dart';

/// Repeating costs (number rental, SaaS plans). Nothing is posted
/// automatically: when one is due you press Record, check the pre-filled
/// entry, and save it — the next due date then moves forward.
class SpendRecurringTab extends ConsumerStatefulWidget {
  const SpendRecurringTab({
    super.key,
    required this.lookups,
    required this.user,
    required this.onChanged,
  });

  final SpendLookups lookups;
  final User user;
  final VoidCallback onChanged;

  @override
  ConsumerState<SpendRecurringTab> createState() => _SpendRecurringTabState();
}

class _SpendRecurringTabState extends ConsumerState<SpendRecurringTab> {
  List<RecurringExpense>? _items;

  @override
  void initState() {
    super.initState();
    ref.read(expenseRepositoryProvider).getRecurring().then((r) {
      if (mounted) setState(() => _items = r);
    });
  }

  bool _isDue(RecurringExpense r) =>
      r.active && !r.nextDue.isAfter(DateTime.now());

  Future<void> _record(RecurringExpense r) async {
    final template = Expense(
      id: const Uuid().v4(),
      vendorId: r.vendorId,
      vendorName: r.vendorName,
      categoryId: r.categoryId,
      entryType: r.entryType,
      date: r.nextDue,
      description: r.description,
      currencyCode: r.currencyCode,
      amount: r.amount,
      taxAmount: r.taxAmount,
      taxKind: r.taxKind,
      inrAmount: r.inrAmount,
      paymentMethod: r.paymentMethod,
      customerId: r.customerId,
      projectId: r.projectId,
      recurringId: r.id,
    );
    final saved = await showExpenseForm(
      context,
      lookups: widget.lookups,
      initial: template,
      title: 'Record: ${r.description.isEmpty ? r.vendorName : r.description}',
      createdBy: widget.user.id,
      saver: (e) => ref.read(expenseRepositoryProvider).recordRecurring(r.id, e),
    );
    if (saved) widget.onChanged();
  }

  Future<void> _edit([RecurringExpense? existing]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RecurringDialog(lookups: widget.lookups, initial: existing),
    );
    if (saved == true) widget.onChanged();
  }

  Future<void> _delete(RecurringExpense r) async {
    await ref.read(expenseRepositoryProvider).deleteRecurring(r.id);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final theme = Theme.of(context);
    if (items == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              'Nothing is recorded automatically — due items show here and on '
              'the Entries tab until you record them.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: () => _edit(),
            icon: const Icon(Icons.add),
            label: const Text('Add recurring'),
          ),
        ]),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No recurring expenses yet (e.g. Vobiz number rental).')),
          ),
        for (final r in items)
          Card(
            child: ListTile(
              leading: Icon(_isDue(r) ? Icons.notification_important : Icons.event_repeat,
                  color: _isDue(r) ? theme.colorScheme.error : null),
              title: Text(r.description.isEmpty ? r.vendorName : '${r.vendorName} — ${r.description}'),
              subtitle: Text([
                '${r.frequency == RecurringExpense.yearly ? 'Yearly' : 'Monthly'} · '
                    '${inr(r.inrAmount)}',
                r.active ? 'next due ${shortDate(r.nextDue)}' : 'paused',
                if (r.customerId != null) widget.lookups.customerName(r.customerId),
              ].join(' · ')),
              trailing: Wrap(spacing: 8, children: [
                if (r.active)
                  FilledButton(
                    onPressed: () => _record(r),
                    child: Text(_isDue(r) ? 'Record now' : 'Record early'),
                  ),
                IconButton(
                    tooltip: 'Edit', icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(r)),
                IconButton(
                    tooltip: 'Delete', icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(r)),
              ]),
            ),
          ),
      ],
    );
  }
}

class _RecurringDialog extends ConsumerStatefulWidget {
  const _RecurringDialog({required this.lookups, this.initial});

  final SpendLookups lookups;
  final RecurringExpense? initial;

  @override
  ConsumerState<_RecurringDialog> createState() => _RecurringDialogState();
}

class _RecurringDialogState extends ConsumerState<_RecurringDialog> {
  final _form = GlobalKey<FormState>();
  String? _vendorId;
  final _vendorName = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _tax = TextEditingController();
  final _inr = TextEditingController();
  String _currency = 'INR';
  String _taxKind = 'none';
  String _type = Expense.typeSubscription;
  String _frequency = RecurringExpense.monthly;
  String? _customerId;
  String? _categoryId;
  late DateTime _nextDue;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _vendorId = r?.vendorId;
    _vendorName.text = r?.vendorName ?? '';
    _description.text = r?.description ?? '';
    _amount.text = r == null ? '' : r.amount.toString();
    _tax.text = r == null || r.taxAmount == 0 ? '' : r.taxAmount.toString();
    _inr.text = r == null || r.currencyCode == 'INR' ? '' : r.inrAmount.toString();
    _currency = r?.currencyCode ?? 'INR';
    _taxKind = r?.taxKind ?? 'none';
    _type = r?.entryType ?? Expense.typeSubscription;
    _frequency = r?.frequency ?? RecurringExpense.monthly;
    _customerId = r?.customerId;
    _categoryId = r?.categoryId;
    _nextDue = r?.nextDue ?? DateTime.now();
    _active = r?.active ?? true;
  }

  double _p(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final tax = _taxKind == 'none' ? 0.0 : _p(_tax);
    await ref.read(expenseRepositoryProvider).saveRecurring(RecurringExpense(
          id: widget.initial?.id ?? const Uuid().v4(),
          vendorId: _vendorId,
          vendorName: _vendorName.text.trim(),
          categoryId: _categoryId,
          entryType: _type,
          description: _description.text.trim(),
          currencyCode: _currency,
          amount: _p(_amount),
          taxAmount: tax,
          taxKind: _taxKind,
          inrAmount: _currency == 'INR' ? _p(_amount) + tax : _p(_inr),
          customerId: _customerId,
          frequency: _frequency,
          nextDue: _nextDue,
          active: _active,
        ));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lookups;
    const gap = SizedBox(height: 12, width: 12);
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add recurring expense' : 'Edit recurring expense'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: l.vendor(_vendorId) == null ? null : _vendorId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Vendor', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Other —')),
                      for (final v in l.vendors) DropdownMenuItem(value: v.id, child: Text(v.name)),
                    ],
                    onChanged: (id) => setState(() {
                      _vendorId = id;
                      final v = l.vendor(id);
                      if (v != null) {
                        _vendorName.text = v.name;
                        _categoryId ??= v.defaultCategoryId;
                        if (v.defaultCurrency != null) _currency = v.defaultCurrency!;
                      }
                    }),
                  ),
                ),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _vendorName,
                    enabled: _vendorId == null,
                    decoration: const InputDecoration(labelText: 'Vendor name', border: OutlineInputBorder()),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                  ),
                ),
              ]),
              gap,
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(
                    labelText: 'Description (e.g. Number rental +91-80…)', border: OutlineInputBorder()),
              ),
              gap,
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                    items: [
                      for (final t in [Expense.typeSubscription, Expense.typeTopup, Expense.typeInvoice, Expense.typeOther])
                        DropdownMenuItem(value: t, child: Text(entryTypeLabel(t))),
                    ],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                gap,
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _frequency,
                    decoration: const InputDecoration(labelText: 'Repeats', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: RecurringExpense.monthly, child: Text('Monthly')),
                      DropdownMenuItem(value: RecurringExpense.yearly, child: Text('Yearly')),
                    ],
                    onChanged: (v) => setState(() => _frequency = v!),
                  ),
                ),
                gap,
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                          context: context,
                          initialDate: _nextDue,
                          firstDate: DateTime(2015),
                          lastDate: DateTime(2100));
                      if (d != null) setState(() => _nextDue = d);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Next due', border: OutlineInputBorder()),
                      child: Text(shortDate(_nextDue)),
                    ),
                  ),
                ),
              ]),
              gap,
              Row(children: [
                SizedBox(
                  width: 100,
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    decoration: const InputDecoration(labelText: 'Currency', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'INR', child: Text('INR')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
                gap,
                Expanded(
                  child: TextFormField(
                    controller: _amount,
                    inputFormatters: decimal,
                    decoration: const InputDecoration(labelText: 'Amount (before tax)', border: OutlineInputBorder()),
                    validator: (v) => _p(_amount) <= 0 ? 'Required' : null,
                  ),
                ),
                gap,
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    value: _taxKind,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Tax', border: OutlineInputBorder()),
                    items: [
                      for (final k in Expense.taxKinds)
                        DropdownMenuItem(value: k, child: Text(taxKindLabel(k))),
                    ],
                    onChanged: (v) => setState(() => _taxKind = v!),
                  ),
                ),
                if (_taxKind != 'none') ...[
                  gap,
                  Expanded(
                    child: TextFormField(
                      controller: _tax,
                      inputFormatters: decimal,
                      decoration: InputDecoration(
                        labelText: 'Tax',
                        border: const OutlineInputBorder(),
                        suffixIcon: TextButton(
                          onPressed: () => setState(
                              () => _tax.text = (_p(_amount) * 0.18).toStringAsFixed(2)),
                          child: const Text('18%'),
                        ),
                      ),
                    ),
                  ),
                ],
              ]),
              if (_currency != 'INR') ...[
                gap,
                TextFormField(
                  controller: _inr,
                  inputFormatters: decimal,
                  decoration: const InputDecoration(
                      labelText: 'Usual INR charged', border: OutlineInputBorder()),
                ),
              ],
              gap,
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: l.customers.any((c) => c.id == _customerId) ? _customerId : null,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Client', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('— Overhead / none —')),
                      for (final c in l.customers) DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => _customerId = v),
                  ),
                ),
                gap,
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Active'),
                    value: _active,
                    onChanged: (v) => setState(() => _active = v),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
