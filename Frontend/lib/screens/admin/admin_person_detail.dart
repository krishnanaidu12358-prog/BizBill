import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/analytics_models.dart';
import '../../services/repo.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../owner/owner_bill_detail.dart';
import 'admin_customer_detail.dart';
import 'admin_user_detail.dart';

/// One real customer (one mobile) and every shop - and shop owner - they buy from.
class AdminPersonDetailScreen extends StatefulWidget {
  const AdminPersonDetailScreen({super.key, required this.repo, required this.mobile});

  final Repo repo;
  final String mobile;

  @override
  State<AdminPersonDetailScreen> createState() => _AdminPersonDetailScreenState();
}

class _AdminPersonDetailScreenState extends State<AdminPersonDetailScreen> {
  late Future<CustomerPersonDetail> _future = widget.repo.adminPerson(widget.mobile);

  Future<void> _reload() async {
    setState(() => _future = widget.repo.adminPerson(widget.mobile));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  void _push(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: AsyncBody<CustomerPersonDetail>(
        future: _future,
        onRefresh: _reload,
        builder: (context, d) {
          final p = d.person;
          final scheme = Theme.of(context).colorScheme;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              ResponsiveCenter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---------------------------------------- who
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            InitialsAvatar(p.name, radius: 28),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.name,
                                      style: const TextStyle(
                                          fontSize: 18, fontWeight: FontWeight.w800)),
                                  Text('+91 ${p.mobile}',
                                      style: TextStyle(color: scheme.onSurfaceVariant)),
                                  const SizedBox(height: 4),
                                  Text(
                                    d.account == null
                                        ? 'No app login (walk-in customer)'
                                        : d.account!.lastLoginAt == null
                                            ? 'Has app login · never signed in'
                                            : 'Has app login · last seen ${relative(d.account!.lastLoginAt)}',
                                    style: TextStyle(
                                        fontSize: 12, color: scheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            if (d.insight.rating != null)
                              Column(
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.star_rounded,
                                          size: 18, color: moneyWarning(context)),
                                      Text(d.insight.rating!.toStringAsFixed(1),
                                          style: const TextStyle(
                                              fontSize: 16, fontWeight: FontWeight.w800)),
                                    ],
                                  ),
                                  Text(d.insight.ratingLabel,
                                      style: TextStyle(
                                          fontSize: 11, color: scheme.onSurfaceVariant)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    KpiGrid(children: [
                      KpiTile(
                        label: 'Shops',
                        value: '${p.shopCount}',
                        icon: Icons.store_outlined,
                        caption: p.shopCount > 1 ? 'Buys from several shops' : 'Single shop',
                      ),
                      KpiTile(
                        label: 'Total billed',
                        value: moneyShort(p.totalBilled),
                        icon: Icons.receipt_long_outlined,
                        accent: SeriesColors.sales(context),
                        caption: '${p.billCount} bills',
                      ),
                      KpiTile(
                        label: 'Owes in total',
                        value: moneyShort(p.totalOutstanding),
                        icon: Icons.account_balance_wallet_outlined,
                        accent: p.totalOutstanding > 0 ? moneyNegative(context) : null,
                        caption: 'Across all shops',
                      ),
                      KpiTile(
                        label: 'Credit to claim',
                        value: moneyShort(p.totalCredit),
                        icon: Icons.card_giftcard,
                        accent: moneyWarning(context),
                        caption: 'Unclaimed store credit',
                      ),
                    ]),

                    if (d.shops.length > 1) ...[
                      const SizedBox(height: 14),
                      ChartCard(
                        title: 'Billed by shop',
                        child: DonutChart(
                          centerLabel: 'Billed',
                          items: d.shops
                              .map((s) => NamedAmount(
                                  name: s.shopName, amount: s.totalBilled, count: s.billCount))
                              .toList(),
                        ),
                      ),
                    ],

                    // ---------------------------------------- shops
                    const SizedBox(height: 18),
                    SectionHeader(
                      'Shops (${d.shops.length})',
                      subtitle: 'Each shop keeps its own record of this customer',
                    ),
                    for (final s in d.shops) ...[
                      _ShopCard(
                        shop: s,
                        onOwner: s.ownerUserId == 0
                            ? null
                            : () => _push(AdminUserDetailScreen(
                                repo: widget.repo, userId: s.ownerUserId)),
                        onRecord: () => _push(AdminCustomerDetailScreen(
                            repo: widget.repo, customerId: s.customerId)),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // ---------------------------------------- bills
                    if (d.recentBills.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const SectionHeader('Recent bills', subtitle: 'From every shop'),
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < d.recentBills.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              ListTile(
                                title: Text(d.recentBills[i].businessName,
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${d.recentBills[i].invoiceNumber}  ·  '
                                    '${dateOf(d.recentBills[i].invoiceDate)}'),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(money(d.recentBills[i].grandTotal),
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    StatusPill(d.recentBills[i].status),
                                  ],
                                ),
                                onTap: () => _push(BillDetailScreen(
                                    repo: widget.repo, invoiceId: d.recentBills[i].id)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop, required this.onRecord, this.onOwner});

  final CustomerPersonShop shop;
  final VoidCallback onRecord;
  final VoidCallback? onOwner;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = shop;

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.storefront, color: scheme.onPrimaryContainer),
            ),
            title: Text(s.shopName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text([
              if ((s.shopCity ?? '').isNotEmpty) s.shopCity!,
              'customer since ${dateOf(s.customerSince)}',
            ].join('  ·  ')),
            trailing: s.isTrusted
                ? Tooltip(
                    message: 'Trusted - limit ${money(s.creditLimit)}',
                    child: Icon(Icons.verified, color: moneyPositive(context)),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                stat('Billed', moneyShort(s.totalBilled)),
                stat('Paid', moneyShort(s.totalPaid), color: moneyPositive(context)),
                stat('Owes', moneyShort(s.outstanding),
                    color: s.outstanding > 0 ? moneyNegative(context) : null),
                stat('Bills', '${s.billCount}'),
              ],
            ),
          ),
          if (s.lastBillOn != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Last bill ${relative(s.lastBillOn)}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: onOwner,
                  icon: const Icon(Icons.badge_outlined, size: 18),
                  label: Text(s.ownerName == null ? 'Owner' : 'Owner: ${s.ownerName}',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
              Container(width: 1, height: 28, color: scheme.outlineVariant),
              Expanded(
                child: TextButton.icon(
                  onPressed: onRecord,
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Full history'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
