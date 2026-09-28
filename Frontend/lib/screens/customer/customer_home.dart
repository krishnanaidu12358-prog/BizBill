import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../models/proof_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import '../statement_screen.dart';
import 'customer_pay_screen.dart';

class CustomerHomeTab extends StatefulWidget {
  const CustomerHomeTab({
    super.key,
    required this.repo,
    required this.onGoToCredits,
  });

  final Repo repo;
  final VoidCallback onGoToCredits;

  @override
  State<CustomerHomeTab> createState() => _CustomerHomeTabState();
}

class _CustomerHomeTabState extends State<CustomerHomeTab> {
  late Future<_HomeBundle> _future = _load();

  Future<_HomeBundle> _load() async {
    final dash = await widget.repo.myDashboard();
    final results = await Future.wait([
      widget.repo.myClaims(),
      widget.repo.myPaymentProofs(),
    ]);
    return _HomeBundle(
      dash,
      results[0] as List<CreditClaim>,
      results[1] as List<PaymentProof>,
    );
  }

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AsyncBody<_HomeBundle>(
      future: _future,
      onRefresh: _reload,
      builder: (context, b) {
        final d = b.dashboard;
        final pending = b.claims.where((c) => c.status == 'Pending').toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Card(
              color: scheme.primaryContainer.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hello, ${d.fullName.split(' ').first}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    Text('+91 ${d.mobile}',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('You owe',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(money(d.totalOutstanding),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: d.totalOutstanding > 0
                                        ? moneyNegative(context)
                                        : moneyPositive(context),
                                  )),
                            ],
                          ),
                        ),
                        Container(
                            width: 1,
                            height: 40,
                            color: scheme.outlineVariant),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Credit available',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(money(d.totalCreditAvailable),
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: moneyPositive(context),
                                  )),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (d.totalCreditAvailable > 0) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: widget.onGoToCredits,
                        icon: const Icon(Icons.redeem),
                        label: const Text('Claim my credit'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (pending.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: scheme.tertiaryContainer.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${pending.length} claim${pending.length == 1 ? '' : 's'} '
                          'waiting for shop approval '
                          '(${money(pending.fold<double>(0, (s, c) => s + c.amount))})',
                          style: const TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: StatCard(
                    label: 'Total bills',
                    value: '${d.billCount}',
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: 'Shops',
                    value: '${d.shopCount}',
                    icon: Icons.storefront_outlined,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Text('Shops you buy from',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),

            if (d.shops.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'No shops linked yet',
                  subtitle:
                      'When a shop bills your mobile number, it shows up here',
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < d.shops.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      _ShopTile(
                        shop: d.shops[i],
                        onStatement: () async {
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StatementScreen(
                                repo: widget.repo,
                                customerView: true,
                                businessId: d.shops[i].businessId,
                              ),
                            ),
                          );
                          if (changed == true) await _reload();
                        },
                        onPay: d.shops[i].outstanding <= 0
                            ? null
                            : () async {
                                final sent = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => CustomerPayScreen(
                                      repo: widget.repo,
                                      businessId: d.shops[i].businessId,
                                      businessName: d.shops[i].businessName,
                                      outstanding: d.shops[i].outstanding,
                                    ),
                                  ),
                                );
                                if (sent == true) await _reload();
                              },
                      ),
                    ],
                  ],
                ),
              ),

            if (b.proofs.isNotEmpty) ...[
              const SizedBox(height: 24),
              MyPaymentProofsSection(
                proofs: b.proofs,
                repo: widget.repo,
                onChanged: _reload,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _HomeBundle {
  _HomeBundle(this.dashboard, this.claims, this.proofs);
  final CustomerDashboard dashboard;
  final List<CreditClaim> claims;
  final List<PaymentProof> proofs;
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop, required this.onStatement, this.onPay});

  final ShopSummary shop;
  final VoidCallback onStatement;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onStatement,
      leading: CircleAvatar(
        backgroundColor: scheme.secondaryContainer,
        child: Icon(Icons.storefront, color: scheme.onSecondaryContainer, size: 20),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(shop.businessName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (shop.isTrusted)
            Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.verified, size: 15, color: moneyPositive(context)),
            ),
        ],
      ),
      subtitle: Text('+91 ${shop.businessMobile}'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (shop.outstanding > 0)
            Text('owe ${money(shop.outstanding)}',
                style: TextStyle(
                    color: moneyNegative(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 13))
          else
            Text('settled',
                style: TextStyle(color: moneyPositive(context), fontSize: 12.5)),
          if (shop.creditAvailable > 0)
            Text('credit ${money(shop.creditAvailable)}',
                style: const TextStyle(fontSize: 11.5)),
          if (onPay != null)
            TextButton(
              onPressed: onPay,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Pay by UPI'),
            ),
        ],
      ),
    );
  }
}

