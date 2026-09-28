import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../models/workforce_models.dart';
import '../../services/repo.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../owner/owner_bill_detail.dart';
import '../pos/pos_screen.dart';
import '../settings_screen.dart';
import '../workers/worker_widgets.dart';

/// Home for a worker login: check in / out, start counter billing, their own
/// bills and attendance. Nothing else of the shop is reachable.
class WorkerShell extends StatefulWidget {
  const WorkerShell({super.key});

  @override
  State<WorkerShell> createState() => _WorkerShellState();
}

class _WorkerShellState extends State<WorkerShell> {
  int _index = 0;
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final repo = Repo(session.api);
    final user = session.user!;
    final scheme = Theme.of(context).colorScheme;

    final pages = [
      _WorkerHome(
        repo: repo,
        user: user,
        key: ValueKey('home$_reload'),
        onBilled: () => setState(() => _reload++),
      ),
      _MyBills(repo: repo, key: ValueKey('bills$_reload')),
      _MyAttendance(repo: repo, key: ValueKey('att$_reload')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(const ['My counter', 'My bills', 'My attendance'][_index]),
            Text('${user.businessName ?? ''} · ${user.fullName}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _reload++),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) async {
              if (v == 'settings') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }
              if (v == 'logout' && context.mounted) await context.read<Session>().logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('+91 ${user.mobile}', style: const TextStyle(fontSize: 12)),
                    Text(user.designation ?? 'Worker', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.palette_outlined),
                    title: Text('Settings & theme')),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                    contentPadding: EdgeInsets.zero, leading: Icon(Icons.logout), title: Text('Log out')),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Counter'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'My bills'),
          NavigationDestination(
              icon: Icon(Icons.event_available_outlined),
              selectedIcon: Icon(Icons.event_available),
              label: 'Attendance'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- home

class _WorkerHome extends StatefulWidget {
  const _WorkerHome({super.key, required this.repo, required this.user, required this.onBilled});

  final Repo repo;
  final UserProfile user;
  final VoidCallback onBilled;

  @override
  State<_WorkerHome> createState() => _WorkerHomeState();
}

class _WorkerHomeState extends State<_WorkerHome> {
  late Future<WorkerToday> _future = widget.repo.myWorkDay();
  bool _busy = false;

  Future<void> _refresh() async {
    setState(() => _future = widget.repo.myWorkDay());
    await _future;
  }

  Future<void> _punch(bool inPunch) async {
    setState(() => _busy = true);
    try {
      final msg = inPunch ? await widget.repo.checkIn() : await widget.repo.checkOut();
      if (mounted) showSnack(context, msg);
      await _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startBilling() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PosScreen(
          repo: widget.repo,
          isWorker: true,
          workerCanGiveUdhaar: widget.user.canGiveUdhaar,
        ),
      ),
    );
    widget.onBilled();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('hh:mm a');

    return AsyncBody<WorkerToday>(
      future: _future,
      onRefresh: _refresh,
      builder: (context, d) {
        final checkedIn = d.checkIn != null;
        final checkedOut = d.checkOut != null;
        return ResponsiveCenter(
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(checkedIn ? Icons.verified_user : Icons.login,
                          size: 36, color: checkedIn ? const Color(0xFF1B7F3B) : scheme.primary),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              !checkedIn
                                  ? (d.status == null ? 'Not checked in yet' : attendanceLabel(d.status))
                                  : checkedOut
                                      ? 'Day done'
                                      : 'At work',
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                            ),
                            Text(
                              [
                                if (checkedIn) 'In ${time.format(DateTime.parse(d.checkIn!).toLocal())}',
                                if (checkedOut) 'Out ${time.format(DateTime.parse(d.checkOut!).toLocal())}',
                                if (!checkedIn) DateFormat('EEEE, dd MMM').format(DateTime.now()),
                              ].join('  ·  '),
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (!checkedIn)
                        FilledButton(
                            onPressed: _busy ? null : () => _punch(true), child: const Text('Check in'))
                      else if (!checkedOut)
                        OutlinedButton(
                            onPressed: _busy ? null : () => _punch(false), child: const Text('Check out')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                  textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                onPressed: _startBilling,
                icon: const Icon(Icons.qr_code_scanner, size: 30),
                label: const Text('Start billing'),
              ),
              const SizedBox(height: 14),
              SectionHeader('My sales today'),
              Row(
                children: [
                  Expanded(child: StatCard(label: 'Sales', value: money(d.salesToday), icon: Icons.trending_up)),
                  Expanded(child: StatCard(label: 'Bills', value: '${d.billsToday}', icon: Icons.receipt_long)),
                ],
              ),
              Row(
                children: [
                  Expanded(child: StatCard(label: 'Cash', value: money(d.cashToday), icon: Icons.payments_outlined)),
                  Expanded(child: StatCard(label: 'UPI', value: money(d.upiToday), icon: Icons.qr_code_2)),
                  Expanded(child: StatCard(label: 'Card', value: money(d.cardToday), icon: Icons.credit_card)),
                ],
              ),
              const SizedBox(height: 6),
              Text('Hand over the cash in the drawer to the owner at the end of your shift.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.outline)),
            ],
          ),
        );
      },
    );
  }
}

// --------------------------------------------------------------------- bills

class _MyBills extends StatefulWidget {
  const _MyBills({super.key, required this.repo});
  final Repo repo;

  @override
  State<_MyBills> createState() => _MyBillsState();
}

class _MyBillsState extends State<_MyBills> {
  late Future<List<Invoice>> _future = widget.repo.invoices();

  Future<void> _refresh() async {
    setState(() => _future = widget.repo.invoices());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return AsyncBody<List<Invoice>>(
      future: _future,
      onRefresh: _refresh,
      builder: (context, list) => list.isEmpty
          ? ListView(children: const [
              SizedBox(height: 80),
              EmptyState(icon: Icons.receipt_long_outlined, title: 'No bills yet', subtitle: 'Bills you make show here.'),
            ])
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final b = list[i];
                return ListTile(
                  title: Text('${b.invoiceNumber} · ${b.customerMobile == '0000000000' ? 'Walk-in' : b.customerName}'),
                  subtitle: Text('${dateTimeOf(b.invoiceDate)} · ${b.paymentMode}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(money(b.grandTotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                      StatusPill(b.status),
                    ],
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillDetailScreen(repo: widget.repo, invoiceId: b.id, staffView: true),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------- attendance

class _MyAttendance extends StatefulWidget {
  const _MyAttendance({super.key, required this.repo});
  final Repo repo;

  @override
  State<_MyAttendance> createState() => _MyAttendanceState();
}

class _MyAttendanceState extends State<_MyAttendance> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<AttendanceMonth> _future = _load();

  Future<AttendanceMonth> _load() => widget.repo.myAttendance(_month.year, _month.month);

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  void _shift(int m) {
    _month = DateTime(_month.year, _month.month + m);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return AsyncBody<AttendanceMonth>(
      future: _future,
      onRefresh: _refresh,
      builder: (context, m) => ResponsiveCenter(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                Expanded(
                  child: Text(DateFormat('MMMM yyyy').format(_month),
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                IconButton(onPressed: isCurrent ? null : () => _shift(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
            Card(child: Padding(padding: const EdgeInsets.all(10), child: AttendanceMonthView(month: m))),
          ],
        ),
      ),
    );
  }
}
