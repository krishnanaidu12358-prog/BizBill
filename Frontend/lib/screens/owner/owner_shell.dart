import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/repo.dart';
import '../../state/session.dart';
import '../pos/pos_screen.dart';
import '../settings_screen.dart';
import '../workers/workers_screen.dart';
import 'shop_profile_screen.dart';
import 'owner_approvals.dart';
import 'owner_bills.dart';
import 'owner_credits.dart';
import 'owner_customers.dart';
import 'owner_dashboard.dart';
import 'owner_expenses.dart';
import 'owner_lookup.dart';
import 'owner_new_bill.dart';
import 'owner_products.dart';
import 'owner_upi_screen.dart';

class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key});

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  int _index = 0;
  int _reloadToken = 0;

  /// Customer payments waiting for approval - shown as a badge.
  int _pendingPayments = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPending());
  }

  Future<void> _loadPending() async {
    try {
      final list = await Repo(context.read<Session>().api).paymentProofs(status: 'Pending');
      if (mounted) setState(() => _pendingPayments = list.length);
    } catch (_) {
      // A missing badge is not worth interrupting the screen for.
    }
  }

  void _refreshAll() {
    setState(() => _reloadToken++);
    _loadPending();
  }

  Future<void> _newBill(Repo repo) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NewBillScreen(repo: repo)),
    );
    if (created == true) _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final repo = Repo(session.api);
    final user = session.user!;
    final scheme = Theme.of(context).colorScheme;

    final pages = [
      OwnerDashboardTab(repo: repo, key: ValueKey('dash$_reloadToken')),
      OwnerBillsTab(repo: repo, key: ValueKey('bills$_reloadToken')),
      OwnerCustomersTab(repo: repo, key: ValueKey('cust$_reloadToken')),
      OwnerCreditsTab(repo: repo, key: ValueKey('credit$_reloadToken')),
      OwnerProductsTab(repo: repo, key: ValueKey('prod$_reloadToken')),
    ];

    const titles = ['Dashboard', 'Bills', 'Customers', 'Credits', 'Products'];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_index]),
            Text(
              user.businessName ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Counter billing (scan & pay)',
            icon: const Icon(Icons.point_of_sale),
            onPressed: () async {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => PosScreen(repo: repo)));
              _refreshAll();
            },
          ),
          IconButton(
            tooltip: 'Workers',
            icon: const Icon(Icons.badge_outlined),
            onPressed: () async {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => WorkersScreen(repo: repo)));
              _refreshAll();
            },
          ),
          IconButton(
            tooltip: 'Customer payments',
            icon: Badge(
              isLabelVisible: _pendingPayments > 0,
              label: Text('$_pendingPayments'),
              child: const Icon(Icons.fact_check_outlined),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => PaymentApprovalsScreen(repo: repo)),
              );
              _refreshAll();
            },
          ),
          IconButton(
            tooltip: 'Check a customer',
            icon: const Icon(Icons.person_search_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CustomerLookupScreen(repo: repo)),
            ),
          ),
          IconButton(
            tooltip: 'Theme',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshAll,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (v) async {
              switch (v) {
                case 'upi':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => OwnerUpiScreen(repo: repo)));
                case 'profile':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ShopProfileScreen(repo: repo)));
                  _refreshAll();
                case 'pos':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => PosScreen(repo: repo)));
                  _refreshAll();
                case 'workers':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => WorkersScreen(repo: repo)));
                  _refreshAll();
                case 'expenses':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ExpensesScreen(repo: repo)));
                  _refreshAll();
                case 'settings':
                  await Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  _refreshAll();
                case 'logout':
                  await context.read<Session>().logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('+91 ${user.mobile}', style: const TextStyle(fontSize: 12)),
                    const Text('Shop owner', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.storefront_outlined),
                  title: Text('Shop profile, logo & signature'),
                ),
              ),
              const PopupMenuItem(
                value: 'pos',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.point_of_sale),
                  title: Text('Counter billing (POS)'),
                ),
              ),
              const PopupMenuItem(
                value: 'workers',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Workers, attendance & salary'),
                ),
              ),
              const PopupMenuItem(
                value: 'upi',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_2),
                  title: Text('UPI payment QR'),
                ),
              ),
              const PopupMenuItem(
                value: 'expenses',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.shopping_bag_outlined),
                  title: Text('Expenses'),
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Settings & theme'),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Log out'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index == 4
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _newBill(repo),
              icon: const Icon(Icons.receipt_long),
              label: const Text('New bill'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Bills'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers'),
          NavigationDestination(
              icon: Icon(Icons.card_giftcard_outlined),
              selectedIcon: Icon(Icons.card_giftcard),
              label: 'Credits'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Stock'),
        ],
      ),
    );
  }
}
