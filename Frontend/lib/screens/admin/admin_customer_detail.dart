import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

/// One customer record in full: who they are, how they got billed, what they
/// paid, the credits they hold and every WhatsApp message sent to them.
class AdminCustomerDetailScreen extends StatefulWidget {
  const AdminCustomerDetailScreen({
    super.key,
    required this.repo,
    required this.customerId,
  });

  final Repo repo;
  final int customerId;

  @override
  State<AdminCustomerDetailScreen> createState() => _AdminCustomerDetailScreenState();
}

class _AdminCustomerDetailScreenState extends State<AdminCustomerDetailScreen> {
  late Future<AdminCustomerDetail> _future =
      widget.repo.adminCustomerDetail(widget.customerId);

  Future<void> _reload() async {
    setState(() => _future = widget.repo.adminCustomerDetail(widget.customerId));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customer details')),
      body: AsyncBody<AdminCustomerDetail>(
        future: _future,
        onRefresh: _reload,
        builder: (context, d) => DefaultTabController(
          length: 4,
          child: Column(
            children: [
              _Header(detail: d),
              const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Invoices'),
                  Tab(text: 'Payments'),
                  Tab(text: 'Credits'),
                  Tab(text: 'Messages'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _BillsTab(detail: d),
                    _PaymentsTab(detail: d),
                    _CreditsTab(detail: d),
                    _MessagesTab(detail: d),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.detail});

  final AdminCustomerDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = detail.customer;
    final i = detail.insight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                            style: const TextStyle(fontSize: 19)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name,
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w700)),
                            Text('+91 ${c.mobile}',
                                style: TextStyle(
                                    fontSize: 13, color: scheme.onSurfaceVariant)),
                            Text('Buys from ${detail.businessName}',
                                style: TextStyle(
                                    fontSize: 12.5, color: scheme.onSurfaceVariant)),
                            if ((c.address ?? '').isNotEmpty)
                              Text(c.address!,
                                  style: TextStyle(
                                      fontSize: 12, color: scheme.outline)),
                          ],
                        ),
                      ),
                      if (i.rating != null)
                        Column(
                          children: [
                            Text(i.rating!.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w800)),
                            Icon(Icons.star, size: 14, color: moneyWarning(context)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          c.isTrusted ? Icons.verified : Icons.help_outline,
                          size: 15,
                          color: c.isTrusted ? moneyPositive(context) : null,
                        ),
                        label: Text(c.isTrusted ? 'Trusted' : 'Not trusted'),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: Icon(
                          detail.account != null
                              ? Icons.phone_iphone
                              : Icons.phonelink_erase,
                          size: 15,
                        ),
                        label: Text(detail.account != null ? 'Has app' : 'No app'),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${i.shopCount} shop(s)'),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(i.ratingLabel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Mini(
                          label: 'Owes this shop',
                          value: money(c.outstandingBalance),
                          tone: c.outstandingBalance > 0
                              ? moneyNegative(context)
                              : moneyPositive(context),
                        ),
                      ),
                      Expanded(
                        child: _Mini(
                          label: 'Credit held',
                          value: money(c.creditBalance),
                          tone: moneyPositive(context),
                        ),
                      ),
                      Expanded(
                        child: _Mini(
                          label: 'Limit',
                          value: money(c.creditLimit),
                        ),
                      ),
                    ],
                  ),
                  if (detail.otherShops.isNotEmpty) ...[
                    const Divider(height: 22),
                    Text('Also buys from',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    for (final s in detail.otherShops)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.storefront_outlined, size: 15),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(s.businessName,
                                    style: const TextStyle(fontSize: 13))),
                            if (s.outstanding > 0)
                              Text('owes ${money(s.outstanding)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: moneyNegative(context))),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.label, required this.value, this.tone});

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: tone)),
        ),
      ],
    );
  }
}

class _BillsTab extends StatelessWidget {
  const _BillsTab({required this.detail});

  final AdminCustomerDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.bills.isEmpty) {
      return const EmptyState(
          icon: Icons.receipt_long_outlined, title: 'No invoices');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: detail.bills.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final b = detail.bills[i];
        return Card(
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(b.invoiceNumber,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${dateOf(b.invoiceDate)}  -  ${b.paymentMode}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(b.grandTotal),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                StatusPill(b.status),
              ],
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Column(
                  children: [
                    for (final it in b.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(
                                    '${it.productName}  x${qty(it.quantity)}',
                                    style: const TextStyle(fontSize: 13))),
                            Text(money(it.lineTotal),
                                style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    MoneyRow('Paid', b.paidAmount, tone: moneyPositive(context)),
                    if (b.balanceAmount > 0)
                      MoneyRow('Balance', b.balanceAmount,
                          bold: true, tone: moneyNegative(context)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.detail});

  final AdminCustomerDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.payments.isEmpty) {
      return const EmptyState(icon: Icons.payments_outlined, title: 'No payments');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: detail.payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final p = detail.payments[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_outlined),
            title: Text(p.receiptNumber,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${dateTimeOf(p.paidOn)}  -  ${p.mode}'
                '${(p.referenceNo ?? '').isEmpty ? '' : '\nRef: ${p.referenceNo}'}'),
            isThreeLine: (p.referenceNo ?? '').isNotEmpty,
            trailing: Text(money(p.amount),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: moneyPositive(context))),
          ),
        );
      },
    );
  }
}

class _CreditsTab extends StatelessWidget {
  const _CreditsTab({required this.detail});

  final AdminCustomerDetail detail;

  @override
  Widget build(BuildContext context) {
    if (detail.credits.isEmpty && detail.claims.isEmpty) {
      return const EmptyState(icon: Icons.card_giftcard, title: 'No credits');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (detail.credits.isNotEmpty) ...[
          const Text('Credits given',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < detail.credits.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(detail.credits[i].creditCode,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      '${dateOf(detail.credits[i].createdAt)}'
                      '${(detail.credits[i].reason ?? '').isEmpty ? '' : '  -  ${detail.credits[i].reason}'}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(money(detail.credits[i].amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13)),
                        const SizedBox(height: 2),
                        StatusPill(detail.credits[i].status),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (detail.claims.isNotEmpty) ...[
          const SizedBox(height: 18),
          const Text('Claims',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var i = 0; i < detail.claims.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    title: Text(money(detail.claims[i].amount),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${detail.claims[i].creditCode}  -  ${relative(detail.claims[i].requestedAt)}'),
                    trailing: StatusPill(detail.claims[i].status),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _MessagesTab extends StatelessWidget {
  const _MessagesTab({required this.detail});

  final AdminCustomerDetail detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (detail.messages.isEmpty) {
      return const EmptyState(
          icon: Icons.chat_outlined, title: 'No WhatsApp messages');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: detail.messages.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final m = detail.messages[i];
        return Card(
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Row(
              children: [
                Expanded(
                    child: Text(m.template,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                StatusPill(m.status),
              ],
            ),
            subtitle: Text(relative(m.createdAt)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(m.body,
                      style: const TextStyle(
                          fontSize: 12.5, height: 1.45, fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
