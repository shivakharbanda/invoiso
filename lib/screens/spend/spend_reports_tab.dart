import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:invoiso/providers/repositories.dart';
import 'package:invoiso_core/models/expense.dart';
import 'package:invoiso_core/models/spend_report_models.dart';

import 'spend_common.dart';

class SpendReportsTab extends ConsumerStatefulWidget {
  const SpendReportsTab({super.key, required this.lookups});

  final SpendLookups lookups;

  @override
  ConsumerState<SpendReportsTab> createState() => _SpendReportsTabState();
}

class _SpendReportsTabState extends ConsumerState<SpendReportsTab> {
  SpendPeriod _period = SpendPeriod.presets()[3]; // this FY
  String _groupBy = 'vendor';

  ProfitAndLoss? _pnl;
  List<MonthlySpendPoint> _monthly = [];
  List<SpendGroupRow> _groups = [];
  List<ClientProfitRow> _clients = [];
  List<InputTaxRow> _itc = [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = ref.read(spendReportRepositoryProvider);
    final from = _period.from, to = _period.to;
    try {
      final results = await Future.wait([
        r.getProfitAndLoss(from, to),
        r.getMonthlySpend(from, to.isAfter(DateTime.now()) ? DateTime.now() : to),
        r.getSpendBy(_groupBy, from, to),
        r.getClientProfitability(from, to),
        r.getInputTax(from, to),
      ]);
      if (!mounted) return;
      setState(() {
        _pnl = results[0] as ProfitAndLoss;
        final monthly = results[1] as List<MonthlySpendPoint>;
        // "All time" starts in 2000 — skip the empty leading months.
        final first = monthly.indexWhere((m) => m.cashOut != 0 || m.cost != 0);
        _monthly = first < 0 ? [] : monthly.sublist(first);
        _groups = results[2] as List<SpendGroupRow>;
        _clients = results[3] as List<ClientProfitRow>;
        _itc = results[4] as List<InputTaxRow>;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _exportCsv() async {
    final entries = await ref.read(expenseRepositoryProvider).getExpenses(
        ExpenseFilter(from: _period.from, to: _period.to), limit: 100000);
    final l = widget.lookups;
    final rows = <List<Object?>>[
      ['Date', 'Vendor', 'GSTIN', 'Type', 'Category', 'Description', 'Ref no',
        'Currency', 'Amount', 'Tax kind', 'Tax', 'INR paid', 'Paid via',
        'Client', 'Project', 'Usage qty', 'Usage unit', 'Notes'],
      for (final e in entries.reversed)
        [
          e.date.toIso8601String().substring(0, 10),
          e.vendorName,
          l.vendor(e.vendorId)?.gstin ?? '',
          entryTypeLabel(e.entryType),
          l.categoryName(e.categoryId),
          e.description,
          e.referenceNo ?? '',
          e.currencyCode,
          e.amount,
          e.taxKind,
          e.taxAmount,
          e.inrAmount,
          e.paymentMethod ?? '',
          l.customerName(e.customerId),
          l.projectName(e.projectId),
          e.usageQty ?? '',
          e.usageUnit ?? '',
          e.notes ?? '',
        ],
    ];
    final csv = const ListToCsvConverter().convert(rows);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export expenses',
      fileName: 'expenses_${_period.from.toIso8601String().substring(0, 10)}'
          '_${_period.to.toIso8601String().substring(0, 10)}.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (path == null) return;
    await File(path).writeAsBytes(utf8.encode('﻿$csv')); // BOM for Excel
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${entries.length} entries to $path')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download),
            label: const Text('Export CSV'),
          ),
        ]),
        const SizedBox(height: 12),
        if (_error != null) Text('Could not load reports: $_error'),
        if (_loading)
          const Padding(
              padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (_pnl != null) ...[
          _pnlCard(theme, _pnl!),
          const SizedBox(height: 16),
          _section(theme, 'Monthly spend', _monthlyChart(theme)),
          const SizedBox(height: 16),
          _section(
            theme,
            'Breakdown',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'vendor', label: Text('Vendor')),
                  ButtonSegment(value: 'category', label: Text('Category')),
                  ButtonSegment(value: 'type', label: Text('Type')),
                  ButtonSegment(value: 'client', label: Text('Client')),
                  ButtonSegment(value: 'project', label: Text('Project')),
                ],
                selected: {_groupBy},
                onSelectionChanged: (s) {
                  _groupBy = s.first;
                  _load();
                },
              ),
              const SizedBox(height: 8),
              _table(
                const ['', 'Cash out', 'Cost', 'Entries'],
                [
                  for (final g in _groups)
                    [g.label, inr(g.cashOut), inr(g.cost), '${g.entryCount}'],
                ],
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _section(
            theme,
            'Profit per client',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                'Revenue = invoices (excl. tax). Cost = products sold + vendor costs '
                'tagged to the client (usage, vendor invoices, subscriptions).',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _table(
                const ['Client', 'Revenue', 'Product cost', 'Vendor cost', 'Profit', 'Margin'],
                [
                  for (final c in _clients)
                    [
                      c.customerName,
                      inr(c.revenue),
                      inr(c.cogs),
                      inr(c.vendorCost),
                      inr(c.profit),
                      c.revenue == 0 ? '—' : '${c.marginPercent.toStringAsFixed(1)}%',
                    ],
                ],
                emphasizeColumn: 4,
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _section(
            theme,
            'Input tax credit (GST paid to vendors)',
            _table(
              const ['Vendor', 'GSTIN', 'Tax', 'Taxable (INR)', 'Tax (INR)', 'Entries'],
              [
                for (final r in _itc)
                  [
                    r.vendorName,
                    r.gstin,
                    taxKindLabel(r.taxKind),
                    inr(r.taxableInr),
                    inr(r.taxInr),
                    '${r.entryCount}',
                  ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _pnlCard(ThemeData theme, ProfitAndLoss p) {
    Widget line(String label, double v, {bool bold = false, bool negative = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)),
          Text('${negative ? '− ' : ''}${inr(v)}',
              style: TextStyle(
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: bold && v < 0 ? theme.colorScheme.error : null)),
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Profit & loss', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(children: [
                Text('Cash basis', style: theme.textTheme.labelLarge),
                line('Revenue (excl. tax)', p.revenue),
                line('Product cost', p.cogs, negative: true),
                line('Vendor cash out', p.vendorCashOut, negative: true),
                const Divider(),
                line('Net', p.netCashBasis, bold: true),
              ]),
            ),
            const SizedBox(width: 32),
            Expanded(
              child: Column(children: [
                Text('Usage basis', style: theme.textTheme.labelLarge),
                line('Revenue (excl. tax)', p.revenue),
                line('Product cost', p.cogs, negative: true),
                line('Vendor cost consumed', p.vendorCost, negative: true),
                const Divider(),
                line('Net', p.netUsageBasis, bold: true),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Cash basis counts wallet top-ups when you pay them; usage basis counts '
            'what you actually consumed. Vendor amounts include GST paid.',
            style: theme.textTheme.bodySmall,
          ),
        ]),
      ),
    );
  }

  Widget _monthlyChart(ThemeData theme) {
    if (_monthly.isEmpty) return const Text('No spend in this period.');
    final max = _monthly
        .map((m) => m.cashOut > m.cost ? m.cashOut : m.cost)
        .fold<double>(0, (a, b) => a > b ? a : b);
    Widget bar(double v, Color c) => LayoutBuilder(
          builder: (context, box) => Container(
            height: 10,
            width: max == 0 ? 0 : box.maxWidth * v / max,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)),
          ),
        );
    final cashColor = theme.colorScheme.primary;
    final costColor = theme.colorScheme.tertiary;
    return Column(children: [
      Row(children: [
        Container(width: 12, height: 12, color: cashColor),
        const Text(' Cash out   '),
        Container(width: 12, height: 12, color: costColor),
        const Text(' Cost consumed'),
      ]),
      const SizedBox(height: 8),
      for (final m in _monthly)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 70, child: Text(m.month)),
            Expanded(
              child: Column(children: [
                bar(m.cashOut, cashColor),
                const SizedBox(height: 2),
                bar(m.cost, costColor),
              ]),
            ),
            SizedBox(
              width: 220,
              child: Text('${inr(m.cashOut, whole: true)} / ${inr(m.cost, whole: true)}',
                  textAlign: TextAlign.right),
            ),
          ]),
        ),
    ]);
  }

  Widget _section(ThemeData theme, String title, Widget child) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );

  Widget _table(List<String> header, List<List<String>> rows, {int? emphasizeColumn}) {
    if (rows.isEmpty) return const Text('Nothing for this period.');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 32,
        dataRowMaxHeight: 40,
        columns: [
          for (var i = 0; i < header.length; i++)
            DataColumn(label: Text(header[i]), numeric: i > 0 && !header[i].contains('GSTIN') && header[i] != 'Tax'),
        ],
        rows: [
          for (final r in rows)
            DataRow(cells: [
              for (var i = 0; i < r.length; i++)
                DataCell(Text(r[i],
                    style: i == emphasizeColumn
                        ? const TextStyle(fontWeight: FontWeight.w700)
                        : null)),
            ]),
        ],
      ),
    );
  }
}
