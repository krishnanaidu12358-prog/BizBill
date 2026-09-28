import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'admin_user_detail.dart';

class AdminBusinessesTab extends StatefulWidget {
  const AdminBusinessesTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<AdminBusinessesTab> createState() => _AdminBusinessesTabState();
}

class _AdminBusinessesTabState extends State<AdminBusinessesTab> {
  final _search = TextEditingController();
  late Future<List<AdminBusiness>> _future = widget.repo.adminBusinesses();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.repo.adminBusinesses(
        search: _search.text.trim().isEmpty ? null : _search.text.trim()));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _toggle(AdminBusiness b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(b.isActive ? 'Suspend this business?' : 'Activate this business?'),
        content: Text(b.isActive
            ? '${b.name} will not be able to log in until you activate it again.'
            : '${b.name} will be able to log in again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
            child: Text(b.isActive ? 'Suspend' : 'Activate'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final msg = await widget.repo.toggleBusiness(b.id);
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
              hintText: 'Search business name or mobile',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: _reload,
              ),
            ),
          ),
        ),
        Expanded(
          child: AsyncBody<List<AdminBusiness>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, list) {
              if (list.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                        icon: Icons.store_outlined, title: 'No businesses found'),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final b = list[i];
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: b.ownerUserId == 0
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminUserDetailScreen(
                                      repo: widget.repo, userId: b.ownerUserId),
                                ),
                              ),
                      child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.name,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700)),
                                    Text(
                                      '${b.ownerName ?? ''}  -  +91 ${b.mobile}'
                                      '${(b.city ?? '').isEmpty ? '' : '  -  ${b.city}'}',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: scheme.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              StatusPill(b.isActive ? 'Active' : 'Cancelled'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _Metric(label: 'Customers', value: '${b.customerCount}'),
                              _Metric(label: 'Bills', value: '${b.invoiceCount}'),
                              _Metric(
                                  label: 'Sales', value: moneyShort(b.totalSales)),
                              _Metric(
                                label: 'Udhaar',
                                value: moneyShort(b.receivable),
                                tone: b.receivable > 0
                                    ? moneyNegative(context)
                                    : null,
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _toggle(b),
                                icon: Icon(
                                    b.isActive
                                        ? Icons.block
                                        : Icons.check_circle_outline,
                                    size: 18),
                                label: Text(b.isActive ? 'Suspend' : 'Activate'),
                              ),
                              const Icon(Icons.chevron_right, size: 20),
                            ],
                          ),
                        ],
                      ),
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
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: tone)),
          ),
        ],
      ),
    );
  }
}

