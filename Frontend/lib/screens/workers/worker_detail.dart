import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../models/workforce_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import '../owner/owner_bill_detail.dart';
import 'worker_form.dart';
import 'worker_widgets.dart';

/// Everything about one worker: attendance month, advances, salary history,
/// their bills, login and on/off switch.
class WorkerDetailScreen extends StatefulWidget {
  const WorkerDetailScreen({super.key, required this.repo, required this.workerId});

  final Repo repo;
  final int workerId;

  @override
  State<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends State<WorkerDetailScreen> {
  Worker? _w;
  String? _error;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  AttendanceMonth? _att;
  List<WorkerAdvance>? _advances;
  List<Payroll>? _payrolls;
  List<Invoice>? _bills;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final w = await widget.repo.worker(widget.workerId);
      if (!mounted) return;
      setState(() => _w = w);
      await Future.wait([_loadMonth(), _loadMoney(), _loadBills()]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadMonth() async {
    try {
      final a = await widget.repo.workerMonth(widget.workerId, _month.year, _month.month);
      if (mounted) setState(() => _att = a);
    } on ApiException catch (_) {}
  }

  Future<void> _loadMoney() async {
    try {
      final r = await Future.wait([
        widget.repo.workerAdvances(widget.workerId),
        widget.repo.payrollHistory(widget.workerId),
      ]);
      if (!mounted) return;
      setState(() {
        _advances = r[0] as List<WorkerAdvance>;
        _payrolls = r[1] as List<Payroll>;
      });
    } on ApiException catch (_) {}
  }

  Future<void> _loadBills() async {
    try {
      final b = await widget.repo.invoices(workerId: widget.workerId);
      if (mounted) setState(() => _bills = b);
    } on ApiException catch (_) {}
  }

  Future<void> _edit() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => WorkerFormScreen(repo: widget.repo, worker: _w)));
    if (ok == true) _load();
  }

  Future<void> _toggle() async {
    final w = _w!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(w.isActive ? 'Switch off ${w.name}?' : 'Switch ${w.name} back on?'),
        content: Text(w.isActive
            ? 'They will be logged out and cannot bill. Their bills, attendance and salary history are kept.'
            : 'Their login (if any) works again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(w.isActive ? 'Switch off' : 'Switch on')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final msg = await widget.repo.toggleWorker(w.id);
      if (mounted) showSnack(context, msg);
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _setLogin() async {
    final w = _w!;
    final c = TextEditingController();
    final pwd = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(w.hasLogin ? 'New password for ${w.name}' : 'Give ${w.name} a counter login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Login mobile: +91 ${w.mobile}'),
            TextField(
              controller: c,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password (min 6)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    if (pwd == null) return;
    if (pwd.length < 6) {
      if (mounted) showSnack(context, 'Password needs at least 6 characters.', error: true);
      return;
    }
    try {
      final msg = await widget.repo.setWorkerLogin(w.id, pwd);
      if (mounted) showSnack(context, msg);
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _giveAdvance() async {
    final amount = TextEditingController();
    final note = TextEditingController();
    var mode = 'Cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Advance to ${_w!.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount', prefixText: '₹ '),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Cash', label: Text('Cash')),
                  ButtonSegment(value: 'UPI', label: Text('UPI')),
                  ButtonSegment(value: 'BankTransfer', label: Text('Bank')),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setD(() => mode = s.first),
              ),
              TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
              const SizedBox(height: 8),
              const Text('Taken back automatically from the next salary.', style: TextStyle(fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Give advance')),
          ],
        ),
      ),
    );
    final v = double.tryParse(amount.text.trim()) ?? 0;
    if (ok != true || v <= 0) return;
    try {
      final msg = await widget.repo.giveAdvance(_w!.id, v, mode, note.text.trim().isEmpty ? null : note.text.trim());
      if (mounted) showSnack(context, msg);
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _cancelAdvance(WorkerAdvance a) async {
    try {
      final msg = await widget.repo.cancelAdvance(a.id);
      if (mounted) showSnack(context, msg);
      _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _paySalary() async {
    try {
      final sheet = await widget.repo.payrollSheet(_month.year, _month.month);
      final row = sheet.where((p) => p.workerId == widget.workerId).toList();
      if (!mounted) return;
      if (row.isEmpty) {
        showSnack(context, 'No salary to pay for this month.', error: true);
        return;
      }
      if (row.first.isPaid) {
        showSnack(context, 'Salary for ${DateFormat('MMMM yyyy').format(_month)} is already paid.');
        return;
      }
      final ok = await showPayDialog(context, widget.repo, row.first);
      if (ok == true) _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final w = _w;

    if (_error != null) {
      return Scaffold(appBar: AppBar(), body: ErrorView(message: _error!, onRetry: _load));
    }
    if (w == null) return Scaffold(appBar: AppBar(), body: const Center(child: CoinLoader()));

    return Scaffold(
      appBar: AppBar(
        title: Text(w.name),
        actions: [
          IconButton(tooltip: 'Edit', onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'login') _setLogin();
              if (v == 'toggle') _toggle();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'login',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.key_outlined),
                  title: Text(w.hasLogin ? 'Reset login password' : 'Give counter login'),
                ),
              ),
              PopupMenuItem(
                value: 'toggle',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(w.isActive ? Icons.person_off_outlined : Icons.person_outline),
                  title: Text(w.isActive ? 'Switch off worker' : 'Switch on worker'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: ListTile(
                  leading: InitialsAvatar(w.name, radius: 24),
                  title: Text('${w.designation ?? 'Worker'}${w.isActive ? '' : '  (switched off)'}'),
                  subtitle: Text([
                    '+91 ${w.mobile}',
                    '${money(w.salaryAmount)}${w.isDaily ? ' per day' : ' per month'}',
                    'Joined ${dateOf(w.joinDate)}',
                    w.hasLogin ? (w.loginActive ? 'Counter login on' : 'Login off') : 'No login',
                    if (w.canGiveUdhaar) 'Can give Udhaar',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: AttendanceChip(status: w.todayStatus, checkIn: w.todayCheckIn),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Open advance',
                      value: money(w.outstandingAdvance),
                      icon: Icons.account_balance_wallet_outlined,
                      tone: w.outstandingAdvance > 0 ? scheme.error : null,
                    ),
                  ),
                  Expanded(
                    child: StatCard(
                      label: 'Bills made',
                      value: _bills == null ? '...' : '${_bills!.length}',
                      icon: Icons.receipt_long,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: w.isActive ? _giveAdvance : null,
                      icon: const Icon(Icons.add_card),
                      label: const Text('Give advance'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _paySalary,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Pay ${DateFormat('MMM').format(_month)} salary'),
                    ),
                  ),
                ],
              ),

              // ---------------------------------------------------- attendance
              SectionHeader('Attendance'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              _month = DateTime(_month.year, _month.month - 1);
                              _loadMonth();
                            },
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(DateFormat('MMMM yyyy').format(_month),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                          ),
                          IconButton(
                            onPressed: DateTime(_month.year, _month.month + 1).isAfter(DateTime.now())
                                ? null
                                : () {
                                    _month = DateTime(_month.year, _month.month + 1);
                                    _loadMonth();
                                  },
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      if (_att == null)
                        const Padding(padding: EdgeInsets.all(20), child: CoinLoader())
                      else
                        AttendanceMonthView(month: _att!),
                    ],
                  ),
                ),
              ),

              // ------------------------------------------------------ advances
              SectionHeader('Advances'),
              if (_advances == null)
                const Center(child: CoinLoader())
              else if (_advances!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('No advances given.', style: TextStyle(color: scheme.outline)),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final a in _advances!)
                        ListTile(
                          dense: true,
                          leading: Icon(
                            a.isCancelled
                                ? Icons.block
                                : a.recovered
                                    ? Icons.check_circle_outline
                                    : Icons.schedule,
                            color: a.isCancelled
                                ? scheme.outline
                                : a.recovered
                                    ? const Color(0xFF1B7F3B)
                                    : scheme.error,
                          ),
                          title: Text(money(a.amount),
                              style: TextStyle(
                                  decoration: a.isCancelled ? TextDecoration.lineThrough : null,
                                  fontWeight: FontWeight.w700)),
                          subtitle: Text('${dateOf(a.advanceDate)} · ${a.paymentMode}'
                              '${(a.note ?? '').isEmpty ? '' : ' · ${a.note}'}'
                              '${a.isCancelled ? ' · cancelled' : a.recovered ? ' · taken back' : ' · open'}'),
                          trailing: !a.isCancelled && !a.recovered
                              ? IconButton(
                                  tooltip: 'Cancel advance',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _cancelAdvance(a),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),

              // ------------------------------------------------------- salary
              SectionHeader('Salary paid'),
              if (_payrolls == null)
                const Center(child: CoinLoader())
              else if (_payrolls!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('No salary paid yet.', style: TextStyle(color: scheme.outline)),
                )
              else
                for (final p in _payrolls!) PayrollCard(payroll: p, showName: false),

              // -------------------------------------------------------- bills
              SectionHeader('Recent bills'),
              if (_bills == null)
                const Center(child: CoinLoader())
              else if (_bills!.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text('No bills made by this worker.', style: TextStyle(color: scheme.outline)),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final b in _bills!.take(20))
                        ListTile(
                          dense: true,
                          title: Text('${b.invoiceNumber} · ${b.customerMobile == '0000000000' ? 'Walk-in' : b.customerName}'),
                          subtitle: Text('${dateTimeOf(b.invoiceDate)} · ${b.paymentMode}'),
                          trailing: Text(money(b.grandTotal),
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: b.isCancelled ? TextDecoration.lineThrough : null)),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => BillDetailScreen(repo: widget.repo, invoiceId: b.id)),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
