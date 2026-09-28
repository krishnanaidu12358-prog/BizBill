import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'owner_bill_detail.dart';

class OwnerBillsTab extends StatefulWidget {
  const OwnerBillsTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<OwnerBillsTab> createState() => _OwnerBillsTabState();
}

class _OwnerBillsTabState extends State<OwnerBillsTab> {
  final _search = TextEditingController();
  String? _status;
  late Future<List<Invoice>> _future = widget.repo.invoices();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.repo.invoices(
          status: _status,
          search: _search.text.trim().isEmpty ? null : _search.text.trim(),
        ));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onSubmitted: (_) => _reload(),
            decoration: InputDecoration(
              hintText: 'Search bill number, customer or mobile',
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
              for (final s in const [null, 'Paid', 'PartiallyPaid', 'Credit', 'Cancelled'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s == null ? 'All' : _label(s)),
                    selected: _status == s,
                    onSelected: (_) {
                      setState(() => _status = s);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: AsyncBody<List<Invoice>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, bills) {
              if (bills.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No bills found',
                      subtitle: 'Try a different filter, or create a new bill',
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: bills.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final b = bills[i];
                  return Card(
                    child: ListTile(
                      title: Text(b.customerName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text('${b.invoiceNumber}  -  ${dateOf(b.invoiceDate)}'),
                          if (b.balanceAmount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('Udhaar ${money(b.balanceAmount)}',
                                  style: TextStyle(
                                      color: moneyNegative(context),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5)),
                            ),
                        ],
                      ),
                      isThreeLine: b.balanceAmount > 0,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(money(b.grandTotal),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 4),
                          StatusPill(b.status),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                BillDetailScreen(repo: widget.repo, invoiceId: b.id),
                          ),
                        );
                        await _reload();
                      },
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

  static String _label(String s) => switch (s) {
        'PartiallyPaid' => 'Part paid',
        'Credit' => 'Udhaar',
        _ => s,
      };
}

