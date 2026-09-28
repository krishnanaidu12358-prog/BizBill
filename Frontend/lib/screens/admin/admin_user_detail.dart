import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'admin_customer_detail.dart';

import '../../models/analytics_models.dart';
import '../../widgets/charts.dart';

/// Everything the Super Admin needs about one shop-owner account.
class AdminUserDetailScreen extends StatefulWidget {
  const AdminUserDetailScreen({super.key, required this.repo, required this.userId});

  final Repo repo;
  final int userId;

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  late Future<AdminUserDetail> _future = widget.repo.adminUserDetail(widget.userId);

  Future<void> _reload() async {
    setState(() => _future = widget.repo.adminUserDetail(widget.userId));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Account details')),
      body: AsyncBody<AdminUserDetail>(
        future: _future,
        onRefresh: _reload,
        builder: (context, d) {
          final biz = d.business;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // --------------------------------------------- the account
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        child: Text(
                          d.account.fullName.isEmpty
                              ? '?'
                              : d.account.fullName[0].toUpperCase(),
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.account.fullName,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                            Text('+91 ${d.account.mobile}',
                                style: TextStyle(
                                    fontSize: 13, color: scheme.onSurfaceVariant)),
                            Text(
                              d.account.lastLoginAt == null
                                  ? 'Never logged in'
                                  : 'Last login ${relative(d.account.lastLoginAt)}',
                              style: TextStyle(
                                  fontSize: 12, color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      StatusPill(d.account.isActive ? 'Active' : 'Cancelled'),
                    ],
                  ),
                ),
              ),

              if (biz == null) ...[
                const SizedBox(height: 24),
                const EmptyState(
                  icon: Icons.person_outline,
                  title: 'Not a shop account',
                  subtitle: 'This login has no business attached to it.',
                ),
              ] else ...[
                // --------------------------------------- shop profile
                const SizedBox(height: 16),
                const _Heading('Shop details'),
                Card(
                  child: Column(
                    children: [
                      _Row(label: 'Shop name', value: biz.name),
                      _Row(label: 'Owner', value: biz.ownerName ?? '-'),
                      _Row(label: 'Mobile', value: '+91 ${biz.mobile}'),
                      if ((biz.email ?? '').isNotEmpty)
                        _Row(label: 'Email', value: biz.email!),
                      _Row(
                        label: 'Address',
                        value: biz.fullAddress.isEmpty ? '-' : biz.fullAddress,
                      ),
                      _Row(label: 'GST', value: biz.gstNumber ?? 'Not registered'),
                      _Row(label: 'Bill prefix', value: biz.invoicePrefix),
                      _Row(label: 'Joined', value: dateOf(biz.createdAt)),
                      _Row(
                        label: 'Status',
                        value: biz.isActive ? 'Active' : 'Suspended',
                        last: true,
                      ),
                    ],
                  ),
                ),

                // ------------------------------------------- the numbers
                const SizedBox(height: 22),
                const _Heading('Business activity'),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.6,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  children: [
                    StatCard(
                        label: 'Customers',
                        value: '${d.stats.customerCount}',
                        icon: Icons.people_outline),
                    StatCard(
                        label: 'Trusted',
                        value: '${d.stats.trustedCustomerCount}',
                        icon: Icons.verified_outlined),
                    StatCard(
                        label: 'Bills',
                        value: '${d.stats.invoiceCount}',
                        icon: Icons.receipt_long_outlined),
                    StatCard(
                        label: 'Products',
                        value: '${d.stats.productCount}',
                        icon: Icons.inventory_2_outlined),
                    StatCard(
                        label: 'Total sales',
                        value: moneyShort(d.stats.totalSales),
                        icon: Icons.trending_up),
                    StatCard(
                        label: 'Collected',
                        value: moneyShort(d.stats.totalCollected),
                        icon: Icons.payments_outlined,
                        tone: moneyPositive(context)),
                    StatCard(
                        label: 'Udhaar owed',
                        value: moneyShort(d.stats.receivable),
                        icon: Icons.account_balance_wallet_outlined,
                        tone: d.stats.receivable > 0 ? moneyNegative(context) : null),
                    StatCard(
                        label: 'Credit unclaimed',
                        value: moneyShort(d.stats.creditUnclaimed),
                        icon: Icons.card_giftcard,
                        tone: moneyWarning(context)),
                    StatCard(
                        label: 'Expenses',
                        value: moneyShort(d.stats.totalExpenses),
                        icon: Icons.shopping_bag_outlined,
                        tone: SeriesColors.expenses(context)),
                    StatCard(
                        label: 'Net',
                        value: moneyShort(d.stats.netAfterExpenses),
                        icon: Icons.savings_outlined,
                        tone: d.stats.netAfterExpenses >= 0
                            ? moneyPositive(context)
                            : moneyNegative(context)),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      _Row(
                          label: 'Credit issued (total)',
                          value: money(d.stats.creditIssued)),
                      _Row(
                          label: 'Claims waiting',
                          value: '${d.stats.pendingClaimCount}'),
                      _Row(
                          label: 'Low stock items',
                          value: '${d.stats.lowStockCount}'),
                      _Row(
                          label: 'WhatsApp sent', value: '${d.stats.whatsAppSent}'),
                      _Row(
                        label: 'Last bill',
                        value: d.stats.lastInvoiceOn == null
                            ? 'None yet'
                            : relative(d.stats.lastInvoiceOn),
                        last: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),
                _ShopAnalytics(repo: widget.repo, businessId: biz.id),

                // -------------------------------------- their customers
                const SizedBox(height: 22),
                _Heading('Customers (${d.customers.length})'),
                if (d.customers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                        icon: Icons.people_outline, title: 'No customers yet'),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < d.customers.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          ListTile(
                            leading: CircleAvatar(
                              radius: 18,
                              child: Text(
                                d.customers[i].name.isEmpty
                                    ? '?'
                                    : d.customers[i].name[0].toUpperCase(),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(d.customers[i].name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (d.customers[i].isTrusted)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Icon(Icons.verified,
                                        size: 14, color: moneyPositive(context)),
                                  ),
                              ],
                            ),
                            subtitle: Text('+91 ${d.customers[i].mobile}'
                                '${d.customers[i].hasAppAccount ? '  -  has app' : ''}'),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (d.customers[i].outstandingBalance > 0)
                                  Text(money(d.customers[i].outstandingBalance),
                                      style: TextStyle(
                                          color: moneyNegative(context),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                if (d.customers[i].creditBalance > 0)
                                  Text('cr ${money(d.customers[i].creditBalance)}',
                                      style: const TextStyle(fontSize: 11)),
                              ],
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminCustomerDetailScreen(
                                  repo: widget.repo,
                                  customerId: d.customers[i].id,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.last = false});

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 110,
                child: Text(label,
                    style:
                        TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }
}

/// The shop's own charts: trend, where money went, what sold.
class _ShopAnalytics extends StatefulWidget {
  const _ShopAnalytics({required this.repo, required this.businessId});

  final Repo repo;
  final int businessId;

  @override
  State<_ShopAnalytics> createState() => _ShopAnalyticsState();
}

class _ShopAnalyticsState extends State<_ShopAnalytics> {
  Period _period = Period.quarter;
  late Future<Analytics> _future = _load();

  Future<Analytics> _load() => widget.repo.adminAnalytics(
        from: _period.from,
        all: _period == Period.all,
        businessId: widget.businessId,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Shop analytics'),
        PeriodSelector(
          value: _period,
          onChanged: (p) => setState(() {
            _period = p;
            _future = _load();
          }),
        ),
        const SizedBox(height: 12),
        FutureBuilder<Analytics>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CoinLoader()),
              );
            }
            if (snap.hasError) {
              return ErrorView(
                message: '${snap.error}',
                onRetry: () => setState(() => _future = _load()),
              );
            }
            final a = snap.data!;
            final k = a.kpis;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KpiGrid(children: [
                  KpiTile(
                    label: 'Sales',
                    value: moneyShort(k.grossSales),
                    icon: Icons.trending_up,
                    accent: SeriesColors.sales(context),
                    caption: '${k.bills} bills',
                  ),
                  KpiTile(
                    label: 'Expenses',
                    value: moneyShort(k.expenditure),
                    icon: Icons.shopping_bag_outlined,
                    accent: SeriesColors.expenses(context),
                  ),
                  KpiTile(
                    label: 'Collected',
                    value: moneyShort(k.collected),
                    icon: Icons.payments_outlined,
                    accent: SeriesColors.collected(context),
                  ),
                  KpiTile(
                    label: 'Net',
                    value: moneyShort(k.net),
                    icon: Icons.savings_outlined,
                    accent: k.net >= 0 ? moneyPositive(context) : moneyNegative(context),
                  ),
                ]),
                const SizedBox(height: 12),
                ChartCard(
                  title: 'Sales vs collections vs expenses',
                  subtitle: '${_period.long} · ${a.granularity == 'Month' ? 'by month' : 'by day'}',
                  child: TrendChart(points: a.trend, height: 190),
                ),
                const SizedBox(height: 12),
                ChartCard(
                  title: 'Expenses by category',
                  child: DonutChart(items: a.expenseCategories, centerLabel: 'Spent'),
                ),
                const SizedBox(height: 12),
                ChartCard(
                  title: 'Best-selling items',
                  child: RankedBars(
                    rows: a.topProducts,
                    color: SeriesColors.collected(context),
                    subtitleOf: (i) => '${a.topProducts[i].count} sold',
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
