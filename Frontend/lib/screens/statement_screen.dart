import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/proof_models.dart';
import '../services/repo.dart';
import '../widgets/common.dart';
import 'customer/customer_pay_screen.dart';

/// A customer's running account with one shop: every unpaid bill with its date
/// and how old it is, plus the combined total due.
///
/// The owner sees a "Send on WhatsApp" action; the customer sees "Pay by UPI".
class StatementScreen extends StatefulWidget {
  const StatementScreen({
    super.key,
    required this.repo,
    required this.customerView,
    this.customerId,
    this.businessId,
  });

  final Repo repo;

  /// true = the customer looking at their own account.
  final bool customerView;
  final int? customerId;
  final int? businessId;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  late Future<Statement> _future = _load();
  bool _changed = false;

  Future<Statement> _load() => widget.customerView
      ? widget.repo.myStatement(widget.businessId!)
      : widget.repo.customerStatement(widget.customerId!);

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _send() async {
    try {
      final data = await widget.repo.sendStatement(widget.customerId!);
      if (!mounted) return;
      showSnack(context, 'Statement sent on WhatsApp.');
      await openWhatsApp(context, data['deepLink'] as String?);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _pay(Statement s, {StatementLine? line}) async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerPayScreen(
          repo: widget.repo,
          businessId: s.businessId,
          businessName: s.businessName,
          outstanding: s.totalDue,
          invoiceId: line?.invoiceId,
          invoiceNumber: line?.invoiceNumber,
          invoiceBalance: line?.balanceAmount,
        ),
      ),
    );
    if (sent == true) {
      _changed = true;
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Account statement'),
          actions: [
            if (!widget.customerView)
              IconButton(
                tooltip: 'Send on WhatsApp',
                icon: const Icon(Icons.send),
                onPressed: _send,
              ),
          ],
        ),
        body: AsyncBody<Statement>(
          future: _future,
          onRefresh: _reload,
          builder: (context, s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Card(
                color: s.totalDue > 0
                    ? scheme.errorContainer.withValues(alpha: 0.45)
                    : scheme.primaryContainer.withValues(alpha: 0.4),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.customerView ? s.businessName : s.customerName,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      if (!widget.customerView)
                        Text('+91 ${s.customerMobile}',
                            style: TextStyle(
                                fontSize: 13, color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 14),
                      Text('Total amount due',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      Text(
                        money(s.totalDue),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: s.totalDue > 0
                              ? moneyNegative(context)
                              : moneyPositive(context),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Fact(
                                label: 'Billed', value: money(s.totalBilled)),
                          ),
                          Expanded(
                            child: _Fact(label: 'Paid', value: money(s.totalPaid)),
                          ),
                          Expanded(
                            child: _Fact(
                              label: 'Oldest',
                              value: s.unpaidBills.isEmpty
                                  ? '-'
                                  : '${s.oldestBillDays}d',
                            ),
                          ),
                        ],
                      ),
                      if (s.creditAvailable > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(Icons.card_giftcard,
                                size: 17, color: moneyPositive(context)),
                            const SizedBox(width: 8),
                            Text(
                              'Credit available: ${money(s.creditAvailable)}',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: moneyPositive(context)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (widget.customerView && s.totalDue > 0) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () => _pay(s),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text('Pay ${money(s.totalDue)} by UPI'),
                ),
              ],

              const SizedBox(height: 22),
              Text(
                s.unpaidBills.isEmpty
                    ? 'Unpaid bills'
                    : 'Unpaid bills (${s.unpaidBills.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),

              if (s.unpaidBills.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: EmptyState(
                    icon: Icons.check_circle_outline,
                    title: 'Everything is settled',
                    subtitle: 'No unpaid bills on this account',
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < s.unpaidBills.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _BillRow(
                          line: s.unpaidBills[i],
                          customerView: widget.customerView,
                          onPay: widget.customerView
                              ? () => _pay(s, line: s.unpaidBills[i])
                              : null,
                        ),
                      ],
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total due',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                            Text(money(s.totalDue),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: moneyNegative(context))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              if (!widget.customerView && s.unpaidBills.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _send,
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Send statement on WhatsApp'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _BillRow extends StatelessWidget {
  const _BillRow({
    required this.line,
    required this.customerView,
    this.onPay,
  });

  final StatementLine line;
  final bool customerView;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stale = line.daysOld > 30;

    return ListTile(
      title: Row(
        children: [
          Flexible(
            child: Text(line.invoiceNumber,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          if (stale)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.warning_amber_rounded,
                  size: 15, color: moneyWarning(context)),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text('${dateOf(line.invoiceDate)}  -  ${line.daysOld} day(s) old',
              style: TextStyle(
                  fontSize: 12.5,
                  color: stale ? moneyWarning(context) : scheme.onSurfaceVariant)),
          Text('Bill ${money(line.grandTotal)}  -  paid ${money(line.paidAmount)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(line.balanceAmount),
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: moneyNegative(context))),
          if (onPay != null)
            TextButton(
              onPressed: onPay,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Pay'),
            ),
        ],
      ),
    );
  }
}
