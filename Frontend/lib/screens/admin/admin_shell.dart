import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/repo.dart';
import '../../state/session.dart';
import '../settings_screen.dart';
import 'admin_businesses.dart';
import 'admin_customers.dart';
import 'admin_overview.dart';
import 'admin_users.dart';
import 'admin_whatsapp.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _index = 0;
  int _reloadToken = 0;

  void _refreshAll() => setState(() => _reloadToken++);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final repo = Repo(session.api);
    final user = session.user!;

    final pages = [
      AdminOverviewTab(
        repo: repo,
        key: ValueKey('ov$_reloadToken'),
        onOpenCustomers: () => setState(() => _index = 3),
      ),
      AdminBusinessesTab(repo: repo, key: ValueKey('biz$_reloadToken')),
      AdminUsersTab(repo: repo, key: ValueKey('usr$_reloadToken')),
      AdminCustomersTab(repo: repo, key: ValueKey('acust$_reloadToken')),
      AdminWhatsAppTab(repo: repo, key: ValueKey('wa$_reloadToken')),
    ];

    const titles = [
      'Analytics',
      'Businesses',
      'Users & accounts',
      'Customers',
      'WhatsApp log'
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titles[_index]),
            Text(
              'Super Admin',
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
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Analytics'),
          NavigationDestination(
              icon: Icon(Icons.store_outlined),
              selectedIcon: Icon(Icons.store),
              label: 'Shops'),
          NavigationDestination(
              icon: Icon(Icons.manage_accounts_outlined),
              selectedIcon: Icon(Icons.manage_accounts),
              label: 'Users'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers'),
          NavigationDestination(
              icon: Icon(Icons.chat_outlined),
              selectedIcon: Icon(Icons.chat),
              label: 'WhatsApp'),
        ],
      ),
    );
  }
}



