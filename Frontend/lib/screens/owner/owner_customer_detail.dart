import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import '../statement_screen.dart';
import 'owner_credits.dart';
import 'owner_customers.dart';
import 'owner_new_bill.dart';

class CustomerDetailScreen extends StatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.repo,
    required this.customerId,
  });

  final Repo repo;
  final int customerId;

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  late Future<_Bundle> _future = _load();

  Future<_Bundle> _load() async {
    final customer = await widget.repo.customer(widget.customerId);
    final results = await Future.wait([
      widget.repo.customerLedger(widget.customerId),
      widget.repo.credits(customerId: widget.customerId),
    ]);
    return _Bundle(
      customer,
      results[0] as List<LedgerRow>,
      results[1] as List<CreditGrant>,
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

  Future<void> _collectPayment(Customer c) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (ctx) => _AmountDialog(
        title: 'Collect payment',
        subtitle: 'Outstanding ${money(c.outstandingBalance)}',
        max: c.outstandingBalance,
        actionLabel: 'Record payment',
      ),
    );
    if (amount == null) return;

    try {
      final msg = await widget.repo.recordPayment({
        'customerId': c.id,
        'amount': amount,
        'mode': 'Cash',
        'sendWhatsApp': true,
      });
      if (!mounted) return;
      showSnack(context, msg);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: AsyncBody<_Bundle>(
        future: _future,
        onRefresh: _reload,
        builder: (context, b) {
          final c = b.customer;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
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
                            child: Text(
                              c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                              style: const TextStyle(fontSize: 19),
                            ),
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
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 13)),
                                if ((c.address ?? '').isNotEmpty)
                                  Text(c.address!,
                                      style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontSize: 12.5)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final saved = await showModalBottomSheet<bool>(
                                context: context,
                                isScrollControlled: true,
                                showDragHandle: true,
                                builder: (_) => CustomerFormSheet(
                                    repo: widget.repo, existing: c),
                              );
                              if (saved == true) await _reload();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(
                            avatar: Icon(
                              c.isTrusted ? Icons.verified : Icons.help_outline,
                              size: 16,
                              color: c.isTrusted ? moneyPositive(context) : null,
                            ),
                            label:
                                Text(c.isTrusted ? 'Trusted' : 'Not trusted'),
                          ),
                          if (c.isTrusted)
                            Chip(label: Text('Limit ${money(c.creditLimit)}')),
                          Chip(
                            avatar: Icon(
                              c.hasAppAccount
                                  ? Icons.phone_iphone
                                  : Icons.phonelink_erase,
                              size: 16,
                            ),
                            label: Text(
                                c.hasAppAccount ? 'Uses the app' : 'No app account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      label: 'Udhaar owed',
                      value: money(c.outstandingBalance),
                      icon: Icons.account_balance_wallet_outlined,
                      tone: c.outstandingBalance > 0
                          ? moneyNegative(context)
                          : moneyPositive(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      label: 'Credit available',
                      value: money(c.creditBalance),
                      icon: Icons.card_giftcard,
                      tone: moneyPositive(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final created = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                NewBillScreen(repo: widget.repo, presetCustomer: c),
                          ),
                        );
                        if (created == true) await _reload();
                      },
                      icon: const Icon(Icons.receipt_long, size: 18),
                      label: const Text('New bill'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: c.outstandingBalance > 0
                          ? () => _collectPayment(c)
                          : null,
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Collect'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StatementScreen(
                        repo: widget.repo,
                        customerView: false,
                        customerId: c.id,
                      ),
                    ),
                  );
                  await _reload();
                },
                icon: const Icon(Icons.description_outlined, size: 18),
                label: Text(c.outstandingBalance > 0
                    ? 'Statement - all unpaid bills'
                    : 'Account statement'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: c.isTrusted
                    ? () async {
                        final issued = await showModalBottomSheet<bool>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => IssueCreditSheet(
                              repo: widget.repo, customer: c),
                        );
                        if (issued == true) await _reload();
                      }
                    : null,
                icon: const Icon(Icons.card_giftcard, size: 18),
                label: Text(c.isTrusted
                    ? 'Give credit'
                    : 'Mark trusted to give credit'),
              ),

              if (b.credits.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('Credits given',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < b.credits.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          title: Text(money(b.credits[i].amount),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${b.credits[i].creditCode}'
                            '${(b.credits[i].reason ?? '').isEmpty ? '' : '  -  ${b.credits[i].reason}'}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusPill(b.credits[i].status),
                              const SizedBox(height: 3),
                              Text('left ${money(b.credits[i].balanceAmount)}',
                                  style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              const Text('Account statement',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (b.ledger.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: EmptyState(
                      icon: Icons.history, title: 'No transactions yet'),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < b.ledger.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _LedgerTile(row: b.ledger[i]),
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

class _Bundle {
  _Bundle(this.customer, this.ledger, this.credits);
  final Customer customer;
  final List<LedgerRow> ledger;
  final List<CreditGrant> credits;
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.row});

  final LedgerRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDebit = row.debit > 0;
    return ListTile(
      dense: true,
      leading: Icon(
        isDebit ? Icons.arrow_upward : Icons.arrow_downward,
        size: 18,
        color: isDebit ? moneyNegative(context) : moneyPositive(context),
      ),
      title: Text(row.description, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(dateTimeOf(row.entryDate),
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${isDebit ? '+' : '-'}${money(isDebit ? row.debit : row.credit)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isDebit ? moneyNegative(context) : moneyPositive(context),
            ),
          ),
          Text('bal ${money(row.runningBalance)}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.subtitle,
    required this.max,
    required this.actionLabel,
  });

  final String title;
  final String subtitle;
  final double max;
  final String actionLabel;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final _controller =
      TextEditingController(text: widget.max.toStringAsFixed(2));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = double.tryParse(_controller.text) ?? 0;
    if (v <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    if (v > widget.max) {
      setState(() => _error = 'Cannot be more than ${money(widget.max)}');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: '₹ ',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(120, 40)),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}


