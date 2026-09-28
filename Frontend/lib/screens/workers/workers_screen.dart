import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/workforce_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'worker_detail.dart';
import 'worker_form.dart';
import 'worker_widgets.dart';

/// Owner's HRMS: Workers · Attendance · Salary · Sales by worker.
class WorkersScreen extends StatelessWidget {
  const WorkersScreen({super.key, required this.repo});

  final Repo repo;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Workers'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.badge_outlined), text: 'Workers'),
              Tab(icon: Icon(Icons.event_available_outlined), text: 'Attendance'),
              Tab(icon: Icon(Icons.currency_rupee), text: 'Salary'),
              Tab(icon: Icon(Icons.leaderboard_outlined), text: 'Sales'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _WorkersTab(repo: repo),
            _AttendanceTab(repo: repo),
            _SalaryTab(repo: repo),
            _SalesTab(repo: repo),
          ],
        ),
      ),
    );
  }
}

// ======================================================================= list

class _WorkersTab extends StatefulWidget {
  const _WorkersTab({required this.repo});
  final Repo repo;

  @override
  State<_WorkersTab> createState() => _WorkersTabState();
}

class _WorkersTabState extends State<_WorkersTab> with AutomaticKeepAliveClientMixin {
  late Future<List<Worker>> _future = _load();
  bool _showInactive = false;

  Future<List<Worker>> _load() => widget.repo.workers(includeInactive: _showInactive);

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  Future<void> _add() async {
    final saved = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => WorkerFormScreen(repo: widget.repo)));
    if (saved == true) _reload();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addWorker',
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add worker'),
      ),
      body: AsyncBody<List<Worker>>(
        future: _future,
        onRefresh: _reload,
        builder: (context, list) => ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
          children: [
            SwitchListTile(
              dense: true,
              title: const Text('Show switched-off workers'),
              value: _showInactive,
              onChanged: (v) {
                _showInactive = v;
                _reload();
              },
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No workers yet',
                  subtitle: 'Add your staff. Give a cashier a login and they can bill at the counter; '
                      'every bill shows who made it.',
                ),
              ),
            for (final w in list)
              Card(
                child: ListTile(
                  leading: InitialsAvatar(w.name),
                  title: Row(
                    children: [
                      Flexible(child: Text(w.name, overflow: TextOverflow.ellipsis)),
                      if (!w.isActive) ...[
                        const SizedBox(width: 6),
                        const StatusPill('Cancelled'),
                      ],
                    ],
                  ),
                  subtitle: Text([
                    w.designation ?? 'Worker',
                    '${money(w.salaryAmount)}${w.isDaily ? '/day' : '/month'}',
                    if (w.hasLogin) 'Counter login',
                    if (w.outstandingAdvance > 0) 'Advance ${money(w.outstandingAdvance)}',
                  ].join('  ·  ')),
                  trailing: AttendanceChip(status: w.todayStatus, checkIn: w.todayCheckIn),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => WorkerDetailScreen(repo: widget.repo, workerId: w.id)),
                    );
                    _reload();
                  },
                ),
              ),
            if (list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Right side shows today\'s attendance.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.outline)),
              ),
          ],
        ),
      ),
    );
  }
}

// ================================================================= attendance

class _AttendanceTab extends StatefulWidget {
  const _AttendanceTab({required this.repo});
  final Repo repo;

  @override
  State<_AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<_AttendanceTab> with AutomaticKeepAliveClientMixin {
  DateTime _day = DateTime.now();
  List<AttendanceRow>? _rows;
  String? _error;
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = null;
      _dirty = false;
    });
    try {
      final rows = await widget.repo.attendanceForDay(_day);
      if (mounted) setState(() => _rows = rows);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d != null) {
      _day = d;
      _load();
    }
  }

  Future<void> _save() async {
    final rows = _rows;
    if (rows == null) return;
    setState(() => _saving = true);
    try {
      final msg = await widget.repo.saveAttendance(_day, rows);
      if (!mounted) return;
      showSnack(context, msg);
      setState(() => _dirty = false);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _markAll(String status) {
    setState(() {
      for (final r in _rows ?? const <AttendanceRow>[]) {
        r.status ??= status;
      }
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final rows = _rows;
    final isToday = DateUtils.isSameDay(_day, DateTime.now());

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    _day = _day.subtract(const Duration(days: 1));
                    _load();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDay,
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text(isToday ? 'Today, ${DateFormat('dd MMM').format(_day)}'
                        : DateFormat('EEE, dd MMM yyyy').format(_day)),
                  ),
                ),
                IconButton(
                  onPressed: isToday
                      ? null
                      : () {
                          _day = _day.add(const Duration(days: 1));
                          _load();
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          if (rows != null && rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _markAll('Present'),
                    icon: const Icon(Icons.done_all),
                    label: const Text('Rest present'),
                  ),
                  TextButton.icon(
                    onPressed: () => _markAll('WeekOff'),
                    icon: const Icon(Icons.weekend_outlined),
                    label: const Text('Rest week off'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : rows == null
                    ? const Center(child: CoinLoader())
                    : rows.isEmpty
                        ? const EmptyState(
                            icon: Icons.event_busy_outlined,
                            title: 'No workers on this day',
                            subtitle: 'Add workers first, or pick a day after they joined.')
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                            itemCount: rows.length,
                            itemBuilder: (_, i) {
                              final r = rows[i];
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(r.workerName,
                                                style: const TextStyle(fontWeight: FontWeight.w700)),
                                          ),
                                          if (r.checkIn != null)
                                            Text(
                                              'In ${DateFormat('hh:mm a').format(DateTime.parse(r.checkIn!).toLocal())}'
                                              '${r.checkOut == null ? '' : '  ·  Out ${DateFormat('hh:mm a').format(DateTime.parse(r.checkOut!).toLocal())}'}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          for (final s in attendanceStatuses)
                                            ChoiceChip(
                                              label: Text(attendanceLabel(s)),
                                              selected: r.status == s,
                                              selectedColor: attendanceColor(s).withValues(alpha: 0.25),
                                              onSelected: (v) => setState(() {
                                                r.status = v ? s : null;
                                                _dirty = true;
                                              }),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: rows == null || rows.isEmpty
          ? null
          : FloatingActionButton.extended(
              heroTag: 'saveAttendance',
              onPressed: _saving || !_dirty ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_dirty ? 'Save attendance' : 'Saved'),
            ),
    );
  }
}

// ===================================================================== salary

class _SalaryTab extends StatefulWidget {
  const _SalaryTab({required this.repo});
  final Repo repo;

  @override
  State<_SalaryTab> createState() => _SalaryTabState();
}

class _SalaryTabState extends State<_SalaryTab> with AutomaticKeepAliveClientMixin {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<Payroll>> _future = _load();

  Future<List<Payroll>> _load() => widget.repo.payrollSheet(_month.year, _month.month);

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  void _shift(int months) {
    _month = DateTime(_month.year, _month.month + months);
    _reload();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(DateFormat('MMMM yyyy').format(_month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<List<Payroll>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, rows) {
              if (rows.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 80),
                  EmptyState(icon: Icons.currency_rupee, title: 'No workers for this month'),
                ]);
              }
              final unpaid = rows.where((r) => !r.isPaid).fold(0.0, (s, r) => s + r.netPay);
              final paid = rows.where((r) => r.isPaid).fold(0.0, (s, r) => s + r.netPay);
              return ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  Row(
                    children: [
                      Expanded(child: StatCard(label: 'Paid', value: money(paid), icon: Icons.check_circle_outline)),
                      Expanded(
                          child: StatCard(
                              label: 'Still to pay',
                              value: money(unpaid),
                              icon: Icons.pending_outlined,
                              tone: Theme.of(context).colorScheme.error)),
                    ],
                  ),
                  for (final r in rows)
                    PayrollCard(
                      payroll: r,
                      onPay: r.isPaid
                          ? null
                          : () async {
                              final ok = await showPayDialog(context, widget.repo, r);
                              if (ok == true) _reload();
                            },
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Salary = monthly pay x paid days / days in month (daily-wage workers: rate x paid days). '
                    'Present, leave and week-off are paid, half day counts half. Advances are taken back automatically.',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ====================================================================== sales

class _SalesTab extends StatefulWidget {
  const _SalesTab({required this.repo});
  final Repo repo;

  @override
  State<_SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<_SalesTab> with AutomaticKeepAliveClientMixin {
  DateTimeRange _range = DateTimeRange(start: DateTime.now(), end: DateTime.now());
  String _preset = 'Today';
  late Future<WorkerSalesReport> _future = _load();

  Future<WorkerSalesReport> _load() => widget.repo.workerSales(_range.start, _range.end);

  Future<void> _reload() async {
    setState(() => _future = _load());
    await _future;
  }

  void _setPreset(String p) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _preset = p;
    _range = switch (p) {
      'Yesterday' => DateTimeRange(
          start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      'This week' => DateTimeRange(start: today.subtract(Duration(days: today.weekday - 1)), end: today),
      'This month' => DateTimeRange(start: DateTime(now.year, now.month), end: today),
      _ => DateTimeRange(start: today, end: today),
    };
    _reload();
  }

  Future<void> _custom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (r != null) {
      _range = r;
      _preset = 'Custom';
      _reload();
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('dd MMM');

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              for (final p in const ['Today', 'Yesterday', 'This week', 'This month'])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                      label: Text(p), selected: _preset == p, onSelected: (_) => _setPreset(p)),
                ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(_preset == 'Custom'
                    ? '${fmt.format(_range.start)} - ${fmt.format(_range.end)}'
                    : 'Pick dates'),
                onPressed: _custom,
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<WorkerSalesReport>(
            future: _future,
            onRefresh: _reload,
            builder: (context, rep) => ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              children: [
                Row(
                  children: [
                    Expanded(child: StatCard(label: 'Total sales', value: money(rep.totalSales), icon: Icons.trending_up)),
                    Expanded(child: StatCard(label: 'Bills', value: '${rep.totalBills}', icon: Icons.receipt_long)),
                  ],
                ),
                for (final r in rep.rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              InitialsAvatar(r.name),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${r.bills} bills · avg ${money(r.averageBill)}'
                                        '${r.cancelledBills > 0 ? ' · ${r.cancelledBills} cancelled' : ''}',
                                        style: TextStyle(fontSize: 12, color: scheme.outline)),
                                  ],
                                ),
                              ),
                              Text(money(r.sales),
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w800, color: scheme.primary)),
                            ],
                          ),
                          if (r.bills > 0) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _mini(context, 'Cash', r.cash, Icons.payments_outlined),
                                _mini(context, 'UPI', r.upi, Icons.qr_code_2),
                                _mini(context, 'Card', r.card, Icons.credit_card),
                                if (r.cardInternational > 0)
                                  _mini(context, 'Intl card', r.cardInternational, Icons.public),
                                if (r.other > 0) _mini(context, 'Other', r.other, Icons.account_balance),
                                if (r.udhaar > 0) _mini(context, 'Udhaar', r.udhaar, Icons.schedule),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mini(BuildContext context, String label, double v, IconData icon) => Chip(
        visualDensity: VisualDensity.compact,
        avatar: Icon(icon, size: 16),
        label: Text('$label ${money(v)}'),
      );
}
