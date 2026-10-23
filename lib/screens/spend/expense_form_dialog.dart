import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'spend_common.dart';

/// Create or edit an expense. Returns true when saved. [saver] replaces the
/// default save (used when recording a recurring template's occurrence).
Future<bool> showExpenseForm(
  BuildContext context, {
  required SpendLookups lookups,
  Expense? initial,
  bool isNew = true,
  String? title,
  Future<void> Function(Expense expense)? saver,
  String? createdBy,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ExpenseFormDialog(
      lookups: lookups,
      initial: initial,
      isNew: isNew,
      title: title,
      saver: saver,
      createdBy: createdBy,
    ),
  );
  return saved ?? false;
}

class _ExpenseFormDialog extends ConsumerStatefulWidget {
  const _ExpenseFormDialog({
    required this.lookups,
    this.initial,
    required this.isNew,
    this.title,
    this.saver,
    this.createdBy,
  });

  final SpendLookups lookups;
  final Expense? initial;
  final bool isNew;
  final String? title;
  final Future<void> Function(Expense expense)? saver;
  final String? createdBy;

  @override
  ConsumerState<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _PendingFile {
  _PendingFile(this.name, this.bytes);

  final String name;
  final List<int> bytes;
}

class _ExpenseFormDialogState extends ConsumerState<_ExpenseFormDialog> {
  final _form = GlobalKey<FormState>();
  late final String _id;
  late String _type;
  String? _vendorId;
  final _vendorName = TextEditingController();
  String? _categoryId;
  late DateTime _date;
  final _description = TextEditingController();
  final _reference = TextEditingController();
  String _currency = 'INR';
  final _amount = TextEditingController();
  final _tax = TextEditingController();
  String _taxKind = 'none';
  final _inr = TextEditingController();
  String? _paymentMethod;
  String? _customerId;
  String? _projectId;
  final _usageQty = TextEditingController();
  String? _usageUnit;
  final _notes = TextEditingController();

  List<ExpenseAttachment> _attachments = [];
  final _pending = <_PendingFile>[];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _id = (widget.isNew ? null : e?.id) ?? const Uuid().v4();
    _type = e?.entryType ?? Expense.typeInvoice;
    _vendorId = e?.vendorId;
    _vendorName.text = e?.vendorName ?? '';
    _categoryId = e?.categoryId;
    _date = e?.date ?? DateTime.now();
    _description.text = e?.description ?? '';
    _reference.text = e?.referenceNo ?? '';
    _currency = e?.currencyCode ?? 'INR';
    _amount.text = e == null || e.amount == 0 ? '' : _num(e.amount);
    _tax.text = e == null || e.taxAmount == 0 ? '' : _num(e.taxAmount);
    _taxKind = e?.taxKind ?? 'none';
    _inr.text = e == null || _currency == 'INR' ? '' : _num(e.inrAmount);
    _paymentMethod = e?.paymentMethod;
    _customerId = e?.customerId;
    _projectId = e?.projectId;
    _usageQty.text = e?.usageQty == null ? '' : _num(e!.usageQty!);
    _usageUnit = e?.usageUnit;
    _notes.text = e?.notes ?? '';
    if (!widget.isNew) _loadAttachments();
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double _parse(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '').trim()) ?? 0;

  double get _total => _parse(_amount) + _parse(_tax);

  double get _inrPaid => _currency == 'INR' ? _total : _parse(_inr);

  Future<void> _loadAttachments() async {
    final list = await ref.read(expenseRepositoryProvider).getAttachments(_id);
    if (mounted) setState(() => _attachments = list);
  }

  void _onVendorChanged(String? id) {
    final v = widget.lookups.vendor(id);
    setState(() {
      _vendorId = id;
      if (v != null) {
        _vendorName.text = v.name;
        _categoryId ??= v.defaultCategoryId;
        if (v.defaultCurrency != null) _currency = v.defaultCurrency!;
        if (widget.isNew && v.billingModel == 'prepaid' &&
            _type == Expense.typeInvoice) {
          _type = Expense.typeTopup;
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _addFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'heic'],
      withData: true,
    );
    if (picked == null) return;
    for (final f in picked.files) {
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${f.name} is over 10 MB — skipped')));
        continue;
      }
      setState(() => _pending.add(_PendingFile(f.name, bytes)));
    }
  }

  Future<void> _openAttachment(ExpenseAttachment a) async {
    final data = await ref.read(expenseRepositoryProvider).getAttachmentData(a.id);
    if (data == null) return;
    final dir = await Directory.systemTemp.createTemp('invoiso_receipt');
    final file = File(p.join(dir.path, a.fileName));
    await file.writeAsBytes(base64Decode(data));
    await OpenFile.open(file.path);
  }

  Future<void> _deleteAttachment(ExpenseAttachment a) async {
    await ref.read(expenseRepositoryProvider).deleteAttachment(a.id);
    await _loadAttachments();
  }

  static String _mime(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.webp' => 'image/webp',
      '.heic' => 'image/heic',
      _ => 'application/octet-stream',
    };
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final usage = _type == Expense.typeUsage;
    final expense = Expense(
      id: _id,
      vendorId: _vendorId,
      vendorName: _vendorName.text.trim(),
      categoryId: _categoryId,
      entryType: _type,
      date: DateTime(_date.year, _date.month, _date.day, 12),
      description: _description.text.trim(),
      referenceNo: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      currencyCode: _currency,
      amount: _parse(_amount),
      taxAmount: _taxKind == 'none' ? 0 : _parse(_tax),
      taxKind: _taxKind,
      inrAmount: _currency == 'INR'
          ? (_parse(_amount) + (_taxKind == 'none' ? 0 : _parse(_tax)))
          : _parse(_inr),
      paymentMethod: usage ? null : _paymentMethod,
      customerId: _customerId,
      projectId: _projectId,
      usageQty: usage && _usageQty.text.trim().isNotEmpty ? _parse(_usageQty) : null,
      usageUnit: usage ? _usageUnit : null,
      recurringId: widget.initial?.recurringId,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      createdBy: widget.initial?.createdBy ?? widget.createdBy,
      createdAt: widget.isNew ? null : widget.initial?.createdAt,
    );
    try {
      final repo = ref.read(expenseRepositoryProvider);
      if (widget.saver != null) {
        await widget.saver!(expense);
      } else {
        await repo.saveExpense(expense);
      }
      for (final f in _pending) {
        await repo.addAttachment(_id, f.name, _mime(f.name), base64Encode(f.bytes));
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.lookups;
    final theme = Theme.of(context);
    final usage = _type == Expense.typeUsage;
    final projects = l.projects
        .where((pr) => !pr.archived || pr.id == _projectId)
        .where((pr) =>
            _customerId == null || pr.customerId == null || pr.customerId == _customerId)
        .toList();
    const gap = SizedBox(height: 12, width: 12);
    final decimal = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];

    return AlertDialog(
      title: Text(widget.title ?? (widget.isNew ? 'New expense' : 'Edit expense')),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: [
                    for (final t in Expense.types)
                      ButtonSegment(value: t, label: Text(entryTypeLabel(t))),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                const SizedBox(height: 6),
                Text(entryTypeHelp(_type),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String?>(
                      value: l.vendor(_vendorId) == null ? null : _vendorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Vendor', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('— Not in vendor list —')),
                        for (final v in l.vendors)
                          DropdownMenuItem(value: v.id, child: Text(v.name)),
                      ],
                      onChanged: _onVendorChanged,
                    ),
                  ),
                  gap,
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _vendorName,
                      enabled: _vendorId == null,
                      decoration: const InputDecoration(
                          labelText: 'Vendor name', border: OutlineInputBorder()),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'Vendor is required' : null,
                    ),
                  ),
                ]),
                gap,
                Row(children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                            labelText: 'Date', border: OutlineInputBorder()),
                        child: Text(
                            '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}'),
                      ),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: l.categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Category', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        for (final c in l.categories)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextFormField(
                      controller: _reference,
                      decoration: const InputDecoration(
                          labelText: 'Invoice / txn no.', border: OutlineInputBorder()),
                    ),
                  ),
                ]),
                gap,
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                      labelText: 'Description', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),
                Text('Amount', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: const InputDecoration(
                          labelText: 'Currency', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'INR', child: Text('INR')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      ],
                      onChanged: (v) => setState(() => _currency = v!),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: TextFormField(
                      controller: _amount,
                      inputFormatters: decimal,
                      decoration: InputDecoration(
                          labelText: _type == Expense.typeTopup
                              ? 'Wallet credit (before tax)'
                              : 'Amount (before tax)',
                          border: const OutlineInputBorder()),
                      onChanged: (_) => setState(() {}),
                      validator: (v) => _parse(_amount) <= 0 ? 'Enter an amount' : null,
                    ),
                  ),
                  gap,
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      value: _taxKind,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Tax', border: OutlineInputBorder()),
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
                          labelText: 'Tax amount',
                          border: const OutlineInputBorder(),
                          suffixIcon: TextButton(
                            onPressed: () => setState(() =>
                                _tax.text = (_parse(_amount) * 0.18).toStringAsFixed(2)),
                            child: const Text('18%'),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ]),
                gap,
                if (_currency != 'INR')
                  TextFormField(
                    controller: _inr,
                    inputFormatters: decimal,
                    decoration: InputDecoration(
                      labelText: usage
                          ? 'INR value of this usage'
                          : 'INR actually charged (bank/card statement)',
                      helperText: _parse(_inr) > 0 && _total > 0
                          ? 'Total $_currency ${_total.toStringAsFixed(2)} · rate ₹${(_parse(_inr) / _total).toStringAsFixed(2)}'
                          : 'Include forex markup so reports match your bank',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) => _parse(_inr) <= 0 ? 'Enter the INR amount' : null,
                  )
                else
                  Text('Total: ${inr(_inrPaid)}',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                if (usage) ...[
                  gap,
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _usageQty,
                        inputFormatters: decimal,
                        decoration: const InputDecoration(
                            labelText: 'Quantity used (optional)',
                            border: OutlineInputBorder()),
                      ),
                    ),
                    gap,
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        value: _usageUnit,
                        decoration: const InputDecoration(
                            labelText: 'Unit', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('—')),
                          for (final u in usageUnits)
                            DropdownMenuItem(value: u, child: Text(u)),
                        ],
                        onChanged: (v) => setState(() => _usageUnit = v),
                      ),
                    ),
                  ]),
                ] else ...[
                  gap,
                  DropdownButtonFormField<String?>(
                    value: _paymentMethod,
                    decoration: const InputDecoration(
                        labelText: 'Paid via', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      for (final m in paymentMethods)
                        DropdownMenuItem(value: m, child: Text(m)),
                    ],
                    onChanged: (v) => setState(() => _paymentMethod = v),
                  ),
                ],
                const SizedBox(height: 20),
                Text('For which client / project? (for profit per client)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: l.customers.any((c) => c.id == _customerId) ? _customerId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Client', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('— Overhead / none —')),
                        for (final c in l.customers)
                          DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ],
                      onChanged: (v) => setState(() {
                        _customerId = v;
                        final pr = l.projects.where((x) => x.id == _projectId).firstOrNull;
                        if (pr?.customerId != null && pr!.customerId != v) _projectId = null;
                      }),
                    ),
                  ),
                  gap,
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: projects.any((x) => x.id == _projectId) ? _projectId : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Project', border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('—')),
                        for (final pr in projects)
                          DropdownMenuItem(value: pr.id, child: Text(pr.name)),
                      ],
                      onChanged: (v) => setState(() {
                        _projectId = v;
                        final pr = l.projects.where((x) => x.id == v).firstOrNull;
                        if (pr?.customerId != null) _customerId = pr!.customerId;
                      }),
                    ),
                  ),
                ]),
                gap,
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: 'Notes', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Text('Receipts', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addFiles,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Attach'),
                  ),
                ]),
                for (final a in _attachments)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.description_outlined),
                    title: Text(a.fileName),
                    subtitle: Text('${(a.size / 1024).toStringAsFixed(0)} KB'),
                    onTap: () => _openAttachment(a),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove',
                      onPressed: () => _deleteAttachment(a),
                    ),
                  ),
                for (final f in _pending)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.upload_file),
                    title: Text(f.name),
                    subtitle: const Text('Will be attached when you save'),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _pending.remove(f)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
