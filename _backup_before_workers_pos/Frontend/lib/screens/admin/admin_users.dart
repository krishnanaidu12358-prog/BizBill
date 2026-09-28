import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'admin_user_detail.dart';

class AdminUsersTab extends StatefulWidget {
  const AdminUsersTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<AdminUsersTab> {
  final _search = TextEditingController();
  String? _role;
  late Future<List<AdminUser>> _future = widget.repo.adminUsers();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.repo.adminUsers(
          role: _role,
          search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        ));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _resetPassword(AdminUser u) async {
    final controller = TextEditingController();
    final newPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset password for ${u.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The account is signed out everywhere and must log in with the '
              'new password. Share it with the account holder directly.',
              style: TextStyle(fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (newPassword == null || newPassword.length < 6) {
      if (newPassword != null && mounted) {
        showSnack(context, 'Password must be at least 6 characters.', error: true);
      }
      return;
    }

    try {
      final msg = await widget.repo.resetPassword(u.id, newPassword);
      if (!mounted) return;
      showSnack(context, msg);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _toggle(AdminUser u) async {
    try {
      final msg = await widget.repo.toggleUser(u.id);
      if (!mounted) return;
      showSnack(context, msg);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'Search name or mobile',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _reload,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final r in const [null, 'SuperAdmin', 'BusinessUser', 'Customer'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_roleLabel(r)),
                    selected: _role == r,
                    onSelected: (_) {
                      setState(() => _role = r);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: AsyncBody<List<AdminUser>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, list) {
              if (list.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                        icon: Icons.manage_accounts_outlined,
                        title: 'No accounts found'),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final u = list[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _roleColor(u.role).withValues(alpha: 0.15),
                        child: Icon(_roleIcon(u.role),
                            size: 19, color: _roleColor(u.role)),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(u.fullName,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          if (!u.isActive)
                            const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: StatusPill('Cancelled'),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '+91 ${u.mobile}  -  ${_roleLabel(u.role)}'
                        '${u.businessName == null ? '' : '\n${u.businessName}'}'
                        '${u.lastLoginAt == null ? '' : '\nLast login ${relative(u.lastLoginAt)}'}',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                      isThreeLine: u.businessName != null || u.lastLoginAt != null,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              AdminUserDetailScreen(repo: widget.repo, userId: u.id),
                        ),
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'reset') _resetPassword(u);
                          if (v == 'toggle') _toggle(u);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'reset',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.lock_reset),
                              title: Text('Reset password'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(u.isActive
                                  ? Icons.block
                                  : Icons.check_circle_outline),
                              title:
                                  Text(u.isActive ? 'Deactivate' : 'Activate'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static String _roleLabel(String? r) => switch (r) {
        null => 'All',
        'SuperAdmin' => 'Super Admin',
        'BusinessUser' => 'Shop owner',
        'Customer' => 'Customer',
        _ => r,
      };

  static IconData _roleIcon(String r) => switch (r) {
        'SuperAdmin' => Icons.shield_outlined,
        'BusinessUser' => Icons.store_outlined,
        _ => Icons.person_outline,
      };

  static Color _roleColor(String r) => switch (r) {
        'SuperAdmin' => const Color(0xFF6A1B9A),
        'BusinessUser' => const Color(0xFF1B6B4A),
        _ => const Color(0xFF1565C0),
      };
}

