import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/repo.dart';
import '../../state/session.dart';
import '../settings_screen.dart';
import 'customer_bills.dart';
import 'customer_credits.dart';
import 'customer_home.dart';
import 'customer_payments.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key});

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  int _index = 0;
  int _reloadToken = 0;

  void _refreshAll() => setState(() => _reloadToken++);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final repo = Repo(session.api);
    final user = session.user!;

    final pages = [
      CustomerHomeTab(
        repo: repo,
        key: ValueKey('home$_reloadToken'),
        onGoToCredits: () => setState(() => _index = 3),
      ),
      CustomerBillsTab(repo: repo, key: ValueKey('bills$_reloadToken')),
      CustomerPaymentsTab(repo: repo, key: ValueKey('pay$_reloadToken')),
      CustomerCreditsTab(repo: repo, key: ValueKey('credits$_reloadToken')),
    ];

    const titles = ['My account', 'My invoices', 'My payments', 'My credits'];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_index]),
            Text(
              user.fullName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
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
              // Captured before the await so no BuildContext crosses the gap.
              final session = context.read<Session>();
              final navigator = Navigator.of(context);
              if (v == 'settings') {
                await navigator.push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
                _refreshAll();
              } else if (v == 'logout') {
                await session.logout();
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
                    Text('+91 ${user.mobile}',
                        style: const TextStyle(fontSize: 12)),
                    const Text('Customer', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long),
              label: 'Invoices'),
          NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Payments'),
          NavigationDestination(
              icon: Icon(Icons.card_giftcard_outlined),
              selectedIcon: Icon(Icons.card_giftcard),
              label: 'Credits'),
        ],
      ),
    );
  }
}

