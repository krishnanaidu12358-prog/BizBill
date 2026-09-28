import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

/// Every rupee this customer has paid, to any shop.
class CustomerPaymentsTab extends StatefulWidget {
  const CustomerPaymentsTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<CustomerPaymentsTab> createState() => _CustomerPaymentsTabState();
}

class _CustomerPaymentsTabState extends State<CustomerPaymentsTab> {
  late Future<List<PaymentRow>> _future = widget.repo.myPayments();

  Future<void> _reload() async {
    setState(() => _future = widget.repo.myPayments());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AsyncBody<List<PaymentRow>>(
      future: _future,
      onRefresh: _reload,
      builder: (context, rows) {
        if (rows.isEmpty) {
          return ListView(
            children: const [
              SizedBox(height: 120),
              EmptyState(
                icon: Icons.payments_outlined,
                title: 'No payments yet',
                subtitle: 'Receipts for money you pay appear here',
              ),
            ],
          );
        }

        final total = rows.fold<double>(0, (s, p) => s + p.amount);

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemCount: rows.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Card(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Total paid',
                              style: TextStyle(
                                  fontSize: 12.5, color: scheme.onSurfaceVariant)),
                          Text(money(total),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: moneyPositive(context),
                              )),
                        ],
                      ),
                      Text('${rows.length} receipt${rows.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }

            final p = rows[i - 1];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(Icons.receipt_outlined,
                      size: 20, color: scheme.onSecondaryContainer),
                ),
                title: Text(p.partyName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${p.receiptNumber}  -  ${dateOf(p.paidOn)}'
                  '${(p.referenceNo ?? '').isEmpty ? '' : '\nRef: ${p.referenceNo}'}',
                ),
                isThreeLine: (p.referenceNo ?? '').isNotEmpty,
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(p.amount),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: moneyPositive(context))),
                    Text(p.mode, style: const TextStyle(fontSize: 11.5)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
