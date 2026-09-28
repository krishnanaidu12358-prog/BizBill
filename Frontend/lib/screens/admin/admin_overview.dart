import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/analytics_models.dart';
import '../../services/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import 'admin_user_detail.dart';

/// Platform analytics - every shop's sales, expenditure, users and customers.
class AdminOverviewTab extends StatefulWidget {
  const AdminOverviewTab({super.key, required this.repo, this.onOpenCustomers});

  final Repo repo;

  /// Jumps to the Customers tab (wired by the shell).
  final VoidCallback? onOpenCustomers;

  @override
  State<AdminOverviewTab> createState() => _AdminOverviewTabState();
}

class _AdminOverviewTabState extends State<AdminOverviewTab> {
  Period _period = Period.month;
  late Future<Analytics> _future = _load();

  Future<Analytics> _load() => widget.repo.adminAnalytics(
        from: _period.from,
        all: _period == Period.all,
      );

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  void _openShop(ShopPerformance s) {
    if (s.ownerUserId == 0) {
      showSnack(context, 'This shop has no owner login yet.', error: true);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminUserDetailScreen(repo: widget.repo, userId: s.ownerUserId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: ResponsiveCenter(
            maxWidth: 1100,
            child: PeriodSelector(
              value: _period,
              onChanged: (p) {
                setState(() => _period = p);
                _reload();
              },
            ),
          ),
        ),
        Expanded(
          child: AsyncBody<Analytics>(
            future: _future,
            onRefresh: _reload,
            builder: (context, a) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                ResponsiveCenter(
                  maxWidth: 1100,
                  child: _Dashboard(
                    a: a,
                    period: _period,
                    onShop: _openShop,
                    onCustomers: widget.onOpenCustomers,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.a,
    required this.period,
    required this.onShop,
    this.onCustomers,
  });

  final Analytics a;
  final Period period;
  final void Function(ShopPerformance) onShop;
  final VoidCallback? onCustomers;

  @override
  Widget build(BuildContext context) {
    final k = a.kpis;
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width >= 900;

    final breakdowns = [
      ChartCard(
        title: 'Collections by mode',
        subtitle: 'How customers paid',
        child: DonutChart(items: a.paymentModes, centerLabel: 'Collected'),
      ),
      ChartCard(
        title: 'Expenditure by category',
        subtitle: 'What shops spent on',
        child: DonutChart(items: a.expenseCategories, centerLabel: 'Spent'),
      ),
      ChartCard(
        title: 'Bills by status',
        subtitle: 'Count of bills',
        child: DonutChart(
          items: a.billStatus
              .map((s) => NamedAmount(name: statusLabel(s.name), amount: s.amount, count: s.count))
              .toList(),
          centerLabel: 'Bills',
          byCount: true,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            '${period.long}  ·  ${dateOf(a.from)} - ${dateOf(a.to)}',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ),

        // ------------------------------------------------------ money
        const SectionHeader('Money'),
        KpiGrid(children: [
          KpiTile(
            label: 'Gross sales',
            value: moneyShort(k.grossSales),
            icon: Icons.trending_up,
            accent: SeriesColors.sales(context),
            caption: '${k.bills} bills · avg ${moneyShort(k.averageBill)}',
          ),
          KpiTile(
            label: 'Expenditure',
            value: moneyShort(k.expenditure),
            icon: Icons.shopping_bag_outlined,
            accent: SeriesColors.expenses(context),
            caption: 'Recorded by shops',
          ),
          KpiTile(
            label: 'Net',
            value: moneyShort(k.net),
            icon: k.net >= 0 ? Icons.savings_outlined : Icons.trending_down,
            accent: k.net >= 0 ? moneyPositive(context) : moneyNegative(context),
            caption: k.grossSales <= 0
                ? '-'
                : '${(k.net / k.grossSales * 100).toStringAsFixed(0)}% of sales',
          ),
          KpiTile(
            label: 'Collected',
            value: moneyShort(k.collected),
            icon: Icons.payments_outlined,
            accent: SeriesColors.collected(context),
            caption: 'Payments received',
          ),
          KpiTile(
            label: 'Udhaar owed',
            value: moneyShort(k.receivable),
            icon: Icons.account_balance_wallet_outlined,
            accent: moneyNegative(context),
            caption: 'Current, all shops',
          ),
          KpiTile(
            label: 'GST billed',
            value: moneyShort(k.tax),
            icon: Icons.receipt_outlined,
            caption: 'Discounts ${moneyShort(k.discounts)}',
          ),
          KpiTile(
            label: 'Credit issued',
            value: moneyShort(k.creditIssued),
            icon: Icons.card_giftcard,
            accent: moneyWarning(context),
            caption: 'Store credit given',
          ),
        ]),

        // ------------------------------------------------------ people
        const SizedBox(height: 18),
        const SectionHeader('Users & customers'),
        KpiGrid(children: [
          KpiTile(
            label: 'Shops',
            value: '${k.shops}',
            icon: Icons.store_outlined,
            caption: '${k.activeShops} active',
          ),
          KpiTile(
            label: 'Shop owners',
            value: '${k.shopOwners}',
            icon: Icons.badge_outlined,
            caption: 'User logins',
          ),
          KpiTile(
            label: 'Customers',
            value: '${k.customers}',
            icon: Icons.people_outline,
            caption: '${k.customersWithApp} use the app',
            onTap: onCustomers,
          ),
          KpiTile(
            label: 'In 2+ shops',
            value: '${k.multiShopCustomers}',
            icon: Icons.hub_outlined,
            caption: '${k.customerRecords} shop-customer links',
            onTap: onCustomers,
          ),
        ]),

        // ------------------------------------------------------ trend
        const SizedBox(height: 18),
        ChartCard(
          title: 'Sales vs collections vs expenditure',
          subtitle: a.granularity == 'Month' ? 'By month' : 'By day',
          child: TrendChart(points: a.trend),
        ),

        // ------------------------------------------------------ shops
        const SizedBox(height: 14),
        ChartCard(
          title: 'Top shops by sales',
          subtitle: 'Tap a shop to see its owner, data and customers',
          child: RankedBars(
            rows: a.topShops
                .map((s) => NamedAmount(name: s.shopName, amount: s.sales, count: s.bills))
                .toList(),
            onTap: (i) => onShop(a.topShops[i]),
            subtitleOf: (i) {
              final s = a.topShops[i];
              return '${s.ownerName ?? '-'} · ${s.customers} customers · '
                  'spent ${compactRs(s.expenses)} · net ${compactRs(s.net)}';
            },
          ),
        ),

        // ------------------------------------------------------ breakdowns
        const SizedBox(height: 14),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < breakdowns.length; i++) ...[
                if (i > 0) const SizedBox(width: 14),
                Expanded(child: breakdowns[i]),
              ],
            ],
          )
        else
          for (final b in breakdowns) ...[b, const SizedBox(height: 14)],

        if (wide) const SizedBox(height: 14),
        ChartCard(
          title: 'Best-selling items',
          subtitle: 'By billed value',
          child: RankedBars(
            rows: a.topProducts,
            color: SeriesColors.collected(context),
            subtitleOf: (i) => '${a.topProducts[i].count} sold',
          ),
        ),

        const SizedBox(height: 14),
        const _PowerBiNote(),
      ],
    );
  }
}

/// Where the same data lives for Power BI Desktop.
class _PowerBiNote extends StatelessWidget {
  const _PowerBiNote();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.secondaryContainer.withValues(alpha: 0.45),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bar_chart_rounded, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Power BI: in Power BI Desktop choose Get Data → SQL Server → BizFlowDb and '
                'load the vw_PowerBI_Sales, _Expenses, _Payments, _Customers and _Shops views.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
