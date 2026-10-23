import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/supplier.dart';
import 'package:uuid/uuid.dart';

import 'spend_common.dart';

/// Vendors (shared with Purchase Bills' suppliers), expense categories and
/// projects.
class SpendSetupTab extends ConsumerWidget {
  const SpendSetupTab({super.key, required this.lookups, required this.onChanged});

  final SpendLookups lookups;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = lookups;

    Widget header(String title, String help, VoidCallback onAdd, String addLabel) =>
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(help, style: theme.textTheme.bodySmall),
            ]),
          ),
          FilledButton.tonalIcon(
              onPressed: onAdd, icon: const Icon(Icons.add), label: Text(addLabel)),
        ]);

    String billing(Supplier v) => switch (v.billingModel) {
          'prepaid' => 'Prepaid wallet',
          'postpaid' => 'Invoiced (postpaid)',
          'subscription' => 'Subscription',
          _ => 'Billing not set',
        };

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        header('Vendors', 'Neev Cloud, Vobiz, AWS… (also used as suppliers for purchase bills)',
            () => _editVendor(context, ref, null), 'Add vendor'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            if (l.vendors.isEmpty)
              const ListTile(title: Text('No vendors yet.')),
            for (final v in l.vendors)
              ListTile(
                leading: Icon(v.billingModel == 'prepaid'
                    ? Icons.account_balance_wallet_outlined
                    : Icons.storefront_outlined),
                title: Text(v.name),
                subtitle: Text([
                  billing(v),
                  v.defaultCurrency ?? 'INR',
                  if (v.defaultCategoryId != null) l.categoryName(v.defaultCategoryId),
                  if (v.gstin.isNotEmpty) 'GSTIN ${v.gstin}',
                  if (v.lowBalanceThreshold != null)
                    'alert below ${money(v.lowBalanceThreshold!, v.defaultCurrency ?? 'INR')}',
                ].join(' · ')),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editVendor(context, ref, v),
              ),
          ]),
        ),
        const SizedBox(height: 24),
        header('Categories', 'Group spend in reports', () => _editCategory(context, ref, null),
            'Add category'),
        const SizedBox(height: 8),
        Card(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in l.categories)
                InputChip(
                  label: Text(c.name),
                  onPressed: () => _editCategory(context, ref, c),
                  onDeleted: () async {
                    await ref.read(expenseRepositoryProvider).deleteCategory(c.id);
                    onChanged();
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        header('Projects', 'Optional finer tagging than clients (e.g. one bot per project)',
            () => _editProject(context, ref, null), 'Add project'),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            if (l.projects.isEmpty) const ListTile(title: Text('No projects yet.')),
            for (final p in l.projects)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(p.name + (p.archived ? ' (archived)' : '')),
                subtitle: Text(p.customerId == null ? 'No client' : l.customerName(p.customerId)),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _editProject(context, ref, p),
              ),
          ]),
        ),
      ],
    );
  }

  Future<void> _editVendor(BuildContext context, WidgetRef ref, Supplier? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final gstin = TextEditingController(text: existing?.gstin ?? '');
    final threshold = TextEditingController(
        text: existing?.lowBalanceThreshold?.toString() ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    var model = existing?.billingModel ?? 'postpaid';
    var currency = existing?.defaultCurrency ?? 'INR';
    var category = existing?.defaultCategoryId;
    final form = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add vendor' : 'Edit vendor'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: model,
                  decoration: const InputDecoration(labelText: 'How you pay them', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'prepaid', child: Text('Prepaid wallet (top-ups, then usage)')),
                    DropdownMenuItem(value: 'postpaid', child: Text('Invoiced after use')),
                    DropdownMenuItem(value: 'subscription', child: Text('Fixed subscription')),
                  ],
                  onChanged: (v) => setState(() => model = v!),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: currency,
                      decoration: const InputDecoration(labelText: 'Bills in', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'INR', child: Text('INR')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      ],
                      onChanged: (v) => setState(() => currency = v!),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: lookups.categories.any((c) => c.id == category) ? category : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Default category', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        for (final c in lookups.categories)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => category = v),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                if (model == 'prepaid') ...[
                  TextFormField(
                    controller: threshold,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                        labelText: 'Warn when wallet below ($currency)',
                        border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: gstin,
                  decoration: const InputDecoration(labelText: 'GSTIN (for input tax credit)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Notes (account id, login email…)', border: OutlineInputBorder()),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (form.currentState!.validate()) Navigator.pop(ctx, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final repo = ref.read(supplierRepositoryProvider);
    final vendor = Supplier(
      id: existing?.id ?? const Uuid().v4(),
      name: name.text.trim(),
      businessName: existing?.businessName ?? '',
      phone: existing?.phone ?? '',
      email: existing?.email ?? '',
      address: existing?.address ?? '',
      gstin: gstin.text.trim(),
      notes: notes.text.trim(),
      billingModel: model,
      defaultCurrency: currency,
      defaultCategoryId: category,
      lowBalanceThreshold: double.tryParse(threshold.text.trim()),
    );
    if (existing == null) {
      await repo.insertSupplier(vendor);
    } else {
      await repo.updateSupplier(vendor);
    }
    onChanged();
  }

  Future<void> _editCategory(
      BuildContext context, WidgetRef ref, ExpenseCategory? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add category' : 'Rename category'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null || result.trim().isEmpty) return;
    await ref.read(expenseRepositoryProvider).saveCategory(ExpenseCategory(
          id: existing?.id ?? const Uuid().v4(),
          name: result.trim(),
          sortOrder: existing?.sortOrder ?? lookups.categories.length,
        ));
    onChanged();
  }

  Future<void> _editProject(BuildContext context, WidgetRef ref, Project? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final notes = TextEditingController(text: existing?.notes ?? '');
    var customer = existing?.customerId;
    var archived = existing?.archived ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Add project' : 'Edit project'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: lookups.customers.any((c) => c.id == customer) ? customer : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Client', border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— None —')),
                  for (final c in lookups.customers)
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) => setState(() => customer = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes', border: OutlineInputBorder()),
              ),
              if (existing != null)
                SwitchListTile(
                  title: const Text('Archived'),
                  value: archived,
                  onChanged: (v) => setState(() => archived = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await ref.read(expenseRepositoryProvider).saveProject(Project(
          id: existing?.id ?? const Uuid().v4(),
          name: name.text.trim(),
          customerId: customer,
          notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
          archived: archived,
        ));
    onChanged();
  }
}
