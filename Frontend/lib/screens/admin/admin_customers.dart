import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/analytics_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'admin_person_detail.dart';

/// Every customer on the platform, one row per person (mobile number) with how
/// many shops they buy from. Tap one to see those shops and their owners.
class AdminCustomersTab extends StatefulWidget {
  const AdminCustomersTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<AdminCustomersTab> createState() => _AdminCustomersTabState();
}

enum _Filter { all, multiShop, owes, app }

class _AdminCustomersTabState extends State<AdminCustomersTab> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  late Future<List<CustomerPerson>> _future = _load();

  Future<List<CustomerPerson>> _load() => widget.repo.adminPeople(
        search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        minShops: _filter == _Filter.multiShop ? 2 : null,
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  List<CustomerPerson> _apply(List<CustomerPerson> all) => switch (_filter) {
        _Filter.owes => all.where((p) => p.totalOutstanding > 0).toList(),
        _Filter.app => all.where((p) => p.hasAppAccount).toList(),
        _ => all,
      };

  static String _label(_Filter f) => switch (f) {
        _Filter.all => 'All',
        _Filter.multiShop => '2+ shops',
        _Filter.owes => 'Owes money',
        _Filter.app => 'Has app',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'Search customer name or mobile',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _reload),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_label(f)),
                    selected: _filter == f,
                    onSelected: (_) {
                      final needsReload =
                          (f == _Filter.multiShop) != (_filter == _Filter.multiShop);
                      setState(() => _filter = f);
                      if (needsReload) _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: AsyncBody<List<CustomerPerson>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, all) {
              final list = _apply(all);
              if (list.isEmpty) {
                return ListView(children: const [
                  SizedBox(height: 120),
                  EmptyState(icon: Icons.people_outline, title: 'No customers found'),
                ]);
              }
              final multi = all.where((p) => p.shopCount > 1).length;
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length + 1,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 2),
                      child: Text(
                        '${list.length} customer${list.length == 1 ? '' : 's'}'
                        '${_filter == _Filter.all && multi > 0 ? '  ·  $multi buy from more than one shop' : ''}',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    );
                  }
                  return ResponsiveCenter(
                    child: _PersonCard(
                      person: list[i - 1],
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminPersonDetailScreen(
                              repo: widget.repo, mobile: list[i - 1].mobile),
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

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final CustomerPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = person;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              InitialsAvatar(p.name, radius: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(p.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                        ),
                        if (p.hasAppAccount) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.phone_iphone, size: 14, color: scheme.primary),
                        ],
                      ],
                    ),
                    Text('+91 ${p.mobile}',
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Chip(
                          icon: Icons.store_outlined,
                          text: '${p.shopCount} shop${p.shopCount == 1 ? '' : 's'}',
                          strong: p.shopCount > 1,
                        ),
                        _Chip(
                          icon: Icons.receipt_long_outlined,
                          text: '${p.billCount} bills · ${moneyShort(p.totalBilled)}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (p.totalOutstanding > 0) ...[
                    Text(moneyShort(p.totalOutstanding),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: moneyNegative(context))),
                    Text('owes', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  ] else
                    Text('settled',
                        style: TextStyle(fontSize: 12, color: moneyPositive(context))),
                  const SizedBox(height: 4),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, this.strong = false});

  final IconData icon;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = strong ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = strong ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 11.5, color: fg, fontWeight: strong ? FontWeight.w700 : null)),
        ],
      ),
    );
  }
}
