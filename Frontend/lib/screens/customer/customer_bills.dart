import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import '../owner/owner_bill_detail.dart';

class CustomerBillsTab extends StatefulWidget {
  const CustomerBillsTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<CustomerBillsTab> createState() => _CustomerBillsTabState();
}

class _CustomerBillsTabState extends State<CustomerBillsTab> {
  bool _unpaidOnly = false;
  late Future<List<Invoice>> _future = widget.repo.myBills();

  Future<void> _reload() async {
    setState(() =>
        _future = widget.repo.myBills(unpaidOnly: _unpaidOnly ? true : null));
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
          child: Row(
            children: [
              FilterChip(
                label: const Text('Unpaid only'),
                selected: _unpaidOnly,
                onSelected: (v) {
                  setState(() => _unpaidOnly = v);
                  _reload();
                },
              ),
            ],
          ),
        ),
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
                      title: 'No bills yet',
                      subtitle: 'Bills from your shops will appear here',
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: bills.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final b = bills[i];
                  return Card(
                    child: ListTile(
                      title: Text(b.businessName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text('${b.invoiceNumber}  -  ${dateOf(b.invoiceDate)}'),
                          if (b.balanceAmount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('You owe ${money(b.balanceAmount)}',
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BillDetailScreen(
                            repo: widget.repo,
                            invoiceId: b.id,
                            customerView: true,
                          ),
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

