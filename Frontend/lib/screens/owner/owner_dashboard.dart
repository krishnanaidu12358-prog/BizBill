import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'owner_bill_detail.dart';
import 'owner_expenses.dart';
import '../../core/theme.dart';
import '../../widgets/charts.dart';

class OwnerDashboardTab extends StatefulWidget {
  const OwnerDashboardTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<OwnerDashboardTab> createState() => _OwnerDashboardTabState();
}

class _OwnerDashboardTabState extends State<OwnerDashboardTab> {
  late Future<OwnerDashboard> _future = widget.repo.ownerDashboard();

  Future<void> _reload() async {
    setState(() => _future = widget.repo.ownerDashboard());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AsyncBody<OwnerDashboard>(
      future: _future,
      onRefresh: _reload,
      builder: (context, d) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (d.pendingClaimCount > 0)
            Card(
              color: scheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.pending_actions),
                title: Text('${d.pendingClaimCount} credit claim'
                    '${d.pendingClaimCount == 1 ? '' : 's'} waiting'),
                subtitle: const Text('Open the Credits tab to approve'),
              ),
            ),
          if (d.pendingClaimCount > 0) const SizedBox(height: 12),

          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.55,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: [
              StatCard(
                label: 'Today sales',
                value: moneyShort(d.todaySales),
                icon: Icons.trending_up,
              ),
              StatCard(
                label: 'Today collection',
                value: moneyShort(d.todayCollection),
                icon: Icons.payments_outlined,
                tone: moneyPositive(context),
              ),
              StatCard(
                label: 'This month',
                value: moneyShort(d.monthSales),
                icon: Icons.calendar_month_outlined,
              ),
              StatCard(
                label: 'Udhaar to collect',
                value: moneyShort(d.totalReceivable),
                icon: Icons.account_balance_wallet_outlined,
                tone: d.totalReceivable > 0 ? moneyNegative(context) : null,
              ),
              StatCard(
                label: 'Credit outstanding',
                value: moneyShort(d.outstandingCreditIssued),
                icon: Icons.card_giftcard,
                tone: moneyWarning(context),
              ),
              StatCard(
                label: 'Bills this month',
                value: '${d.invoiceCountThisMonth}',
                icon: Icons.receipt_long_outlined,
              ),
            ],
          ),

          const SizedBox(height: 12),
          _NetCard(
            sales: d.monthSales,
            expenses: d.monthExpenses,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ExpensesScreen(repo: widget.repo)));
              await _reload();
            },
          ),

          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.people_outline,
                  label: 'Customers',
                  value: '${d.customerCount}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.inventory_2_outlined,
                  label: 'Products',
                  value: '${d.productCount}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MiniStat(
                  icon: Icons.warning_amber_rounded,
                  label: 'Low stock',
                  value: '${d.lowStockCount}',
                  tone: d.lowStockCount > 0 ? moneyWarning(context) : null,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Text('Recent bills',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          if (d.recentInvoices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No bills yet',
                subtitle: 'Tap "New bill" to create the first one',
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < d.recentInvoices.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _InvoiceTile(
                      invoice: d.recentInvoices[i],
                      repo: widget.repo,
                      onChanged: _reload,
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
    this.tone,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 20, color: tone ?? scheme.onSurfaceVariant),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: tone)),
            Text(label,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({
    required this.invoice,
    required this.repo,
    required this.onChanged,
  });

  final Invoice invoice;
  final Repo repo;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(invoice.customerName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${invoice.invoiceNumber}  -  ${relative(invoice.invoiceDate)}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(invoice.grandTotal),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          StatusPill(invoice.status),
        ],
      ),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BillDetailScreen(repo: repo, invoiceId: invoice.id),
          ),
        );
        await onChanged();
      },
    );
  }
}


/// This month in one line: what came in, what went out, what is left.
class _NetCard extends StatelessWidget {
  const _NetCard({required this.sales, required this.expenses, required this.onTap});

  final double sales;
  final double expenses;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = sales - expenses;

    Widget part(String label, double v, Color c) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 5),
                Text(label, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ]),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(moneyShort(v),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        );

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('This month',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  Text('Expenses', style: TextStyle(fontSize: 12.5, color: scheme.primary)),
                  Icon(Icons.chevron_right, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  part('Sales', sales, SeriesColors.sales(context)),
                  part('Expenses', expenses, SeriesColors.expenses(context)),
                  part('Net', net, net >= 0 ? moneyPositive(context) : moneyNegative(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
