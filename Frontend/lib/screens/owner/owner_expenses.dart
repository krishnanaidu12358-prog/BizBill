import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/analytics_models.dart';
import '../../services/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

/// What the shop spends - rent, stock purchases, salaries. Sales minus this is the net.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.repo});

  final Repo repo;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Period _period = Period.month;
  late Future<ExpenseSummary> _future = _load();

  Future<ExpenseSummary> _load() => widget.repo.expenses(
        // "All" still needs a start date - the API defaults to this month otherwise.
        from: _period.from ?? DateTime(2000),
        to: DateTime.now(),
      );

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _AddExpenseSheet(repo: widget.repo),
    );
    if (saved == true) await _reload();
  }

  Future<void> _cancel(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this expense?'),
        content: Text('${e.category} · ${money(e.amount)} on ${dateOf(e.expenseDate)}.\n'
            'It stays in the audit log but no longer counts in totals.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel it'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await widget.repo.cancelExpense(e.id);
      if (!mounted) return;
      showSnack(context, msg);
      await _reload();
    } on ApiException catch (err) {
      if (mounted) showSnack(context, err.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: ResponsiveCenter(
              child: PeriodSelector(
                value: _period,
                onChanged: (p) {
                  setState(() => _period = p);
                  _reload();
                },
              ),
            ),
          ),
          Expanded(
            child: AsyncBody<ExpenseSummary>(
              future: _future,
              onRefresh: _reload,
              builder: (context, s) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  ResponsiveCenter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          color: SeriesColors.expenses(context).withValues(alpha: 0.10),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.shopping_bag_outlined,
                                    color: SeriesColors.expenses(context)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Spent · ${_period.long}',
                                          style: TextStyle(
                                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                                      Text(money(s.total),
                                          style: const TextStyle(
                                              fontSize: 24, fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                ),
                                Text('${s.count} entries',
                                    style: TextStyle(color: scheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ),
                        if (s.byCategory.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ChartCard(
                            title: 'By category',
                            child: DonutChart(items: s.byCategory, centerLabel: 'Spent'),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const SectionHeader('Entries'),
                        if (s.items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 30),
                            child: EmptyState(
                              icon: Icons.receipt_outlined,
                              title: 'No expenses in this period',
                              subtitle: 'Record rent, stock purchases or salaries to see your real net.',
                            ),
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (var i = 0; i < s.items.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: SeriesColors.expenses(context)
                                          .withValues(alpha: 0.12),
                                      child: Icon(_iconFor(s.items[i].category),
                                          size: 20, color: SeriesColors.expenses(context)),
                                    ),
                                    title: Text(s.items[i].category,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text([
                                      dateOf(s.items[i].expenseDate),
                                      s.items[i].paymentMode,
                                      if ((s.items[i].paidTo ?? '').isNotEmpty) s.items[i].paidTo!,
                                      if ((s.items[i].note ?? '').isNotEmpty) s.items[i].note!,
                                    ].join('  ·  ')),
                                    trailing: Text(money(s.items[i].amount),
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    onLongPress: () => _cancel(s.items[i]),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        if (s.items.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Text('Long-press an entry to cancel it.',
                                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconFor(String category) => switch (category) {
      'Stock purchase' => Icons.inventory_2_outlined,
      'Rent' => Icons.home_work_outlined,
      'Salary' => Icons.badge_outlined,
      'Electricity' => Icons.bolt_outlined,
      'Transport' => Icons.local_shipping_outlined,
      'Maintenance' => Icons.build_outlined,
      'Marketing' => Icons.campaign_outlined,
      _ => Icons.receipt_outlined,
    };

class _AddExpenseSheet extends StatefulWidget {
  const _AddExpenseSheet({required this.repo});

  final Repo repo;

  @override
  State<_AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<_AddExpenseSheet> {
  static const _fallbackCategories = [
    'Stock purchase', 'Rent', 'Salary', 'Electricity',
    'Transport', 'Maintenance', 'Marketing', 'Other',
  ];

  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _paidTo = TextEditingController();
  final _note = TextEditingController();
  List<String> _categories = _fallbackCategories;
  String _category = 'Stock purchase';
  String _mode = 'Cash';
  DateTime _date = DateTime.now();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.repo.expenseCategories().then((c) {
      if (mounted && c.isNotEmpty) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _amount.dispose();
    _paidTo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final now = DateTime.now();
      final when = DateTime(_date.year, _date.month, _date.day, now.hour, now.minute);
      final msg = await widget.repo.createExpense({
        'category': _category,
        'amount': double.parse(_amount.text),
        'expenseDate': when.toUtc().toIso8601String(),
        'paymentMode': _mode,
        'paidTo': _paidTo.text.trim().isEmpty ? null : _paidTo.text.trim(),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      if (!mounted) return;
      showSnack(context, msg);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Add expense',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _categories)
                    ChoiceChip(
                      avatar: Icon(_iconFor(c), size: 16),
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
                validator: (v) =>
                    (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter the amount spent' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event, size: 18),
                      label: Text(dateOf(_date.toIso8601String())),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _mode,
                      decoration: const InputDecoration(labelText: 'Paid by'),
                      items: const [
                        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                        DropdownMenuItem(value: 'Card', child: Text('Card')),
                        DropdownMenuItem(value: 'Bank', child: Text('Bank')),
                      ],
                      onChanged: (v) => setState(() => _mode = v ?? 'Cash'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _paidTo,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Paid to (optional)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? CoinLoader(size: 18)
                    : const Icon(Icons.check),
                label: Text(_busy ? 'Saving...' : 'Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
