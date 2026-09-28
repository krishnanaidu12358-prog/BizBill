import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

class OwnerCreditsTab extends StatefulWidget {
  const OwnerCreditsTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<OwnerCreditsTab> createState() => _OwnerCreditsTabState();
}

class _OwnerCreditsTabState extends State<OwnerCreditsTab> {
  late Future<_CreditBundle> _future = _load();

  Future<_CreditBundle> _load() async {
    final results = await Future.wait([
      widget.repo.credits(),
      widget.repo.claims(),
    ]);
    return _CreditBundle(
      results[0] as List<CreditGrant>,
      results[1] as List<CreditClaim>,
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

  Future<void> _issue() async {
    final customers = await widget.repo.customers();
    final trusted = customers.where((c) => c.isTrusted).toList();
    if (!mounted) return;

    if (trusted.isEmpty) {
      showSnack(
          context,
          'No trusted customers yet. Open a customer and turn on "Trusted" first.',
          error: true);
      return;
    }

    final customer = await showModalBottomSheet<Customer>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Give credit to',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          for (final c in trusted)
            ListTile(
              leading: CircleAvatar(
                  child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase())),
              title: Text(c.name),
              subtitle: Text('+91 ${c.mobile}  -  limit ${money(c.creditLimit)}'),
              trailing: c.creditBalance > 0
                  ? Text('has ${money(c.creditBalance)}',
                      style: const TextStyle(fontSize: 12))
                  : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
        ],
      ),
    );

    if (customer == null || !mounted) return;

    final issued = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => IssueCreditSheet(repo: widget.repo, customer: customer),
    );
    if (issued == true) await _reload();
  }

  Future<void> _process(CreditClaim claim, bool approve) async {
    String? remarks;
    if (!approve) {
      remarks = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final c = TextEditingController();
          return AlertDialog(
            title: const Text('Reject claim'),
            content: TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
                child: const Text('Reject'),
              ),
            ],
          );
        },
      );
      if (remarks == null) return;
    }

    try {
      final msg = await widget.repo.processClaim(claim.id, approve, remarks);
      if (!mounted) return;
      showSnack(context, msg);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AsyncBody<_CreditBundle>(
        future: _future,
        onRefresh: _reload,
        builder: (context, b) {
          final pending =
              b.claims.where((c) => c.status == 'Pending').toList();
          final history =
              b.claims.where((c) => c.status != 'Pending').toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (pending.isNotEmpty) ...[
                Text('Claims to approve (${pending.length})',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                for (final c in pending)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      color: Theme.of(context)
                          .colorScheme
                          .tertiaryContainer
                          .withValues(alpha: 0.35),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(c.customerName,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                ),
                                Text(money(c.amount),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${c.creditCode}  -  +91 ${c.customerMobile}  -  ${relative(c.requestedAt)}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            if ((c.remarks ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('"${c.remarks}"',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        fontStyle: FontStyle.italic)),
                              ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => _process(c, false),
                                  child: const Text('Reject'),
                                ),
                                const SizedBox(width: 6),
                                FilledButton(
                                  onPressed: () => _process(c, true),
                                  style: FilledButton.styleFrom(
                                      minimumSize: const Size(110, 40)),
                                  child: const Text('Approve'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              const Text('Credits issued',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (b.grants.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: EmptyState(
                    icon: Icons.card_giftcard,
                    title: 'No credits given yet',
                    subtitle: 'Use the + button to give credit to a trusted customer',
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < b.grants.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _GrantTile(
                          grant: b.grants[i],
                          repo: widget.repo,
                          onChanged: _reload,
                        ),
                      ],
                    ],
                  ),
                ),

              if (history.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text('Past claims',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < history.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          title: Text(history[i].customerName),
                          subtitle: Text(
                              '${history[i].creditCode}  -  ${relative(history[i].requestedAt)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(money(history[i].amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 2),
                              StatusPill(history[i].status),
                            ],
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'issueCredit',
        onPressed: _issue,
        child: const Icon(Icons.add_card),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

class _CreditBundle {
  _CreditBundle(this.grants, this.claims);
  final List<CreditGrant> grants;
  final List<CreditClaim> claims;
}

class _GrantTile extends StatelessWidget {
  const _GrantTile({
    required this.grant,
    required this.repo,
    required this.onChanged,
  });

  final CreditGrant grant;
  final Repo repo;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(grant.customerName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text('${grant.creditCode}  -  ${dateOf(grant.createdAt)}'),
          Text(
            'Given ${money(grant.amount)}  -  claimed ${money(grant.claimedAmount)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(grant.balanceAmount),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          StatusPill(grant.status),
        ],
      ),
      onLongPress: grant.status == 'Active' || grant.status == 'PartiallyClaimed'
          ? () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cancel this credit?'),
                  content: Text(
                      '${money(grant.balanceAmount)} of unclaimed credit will be '
                      'withdrawn from ${grant.customerName}.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep')),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
                      child: const Text('Cancel it'),
                    ),
                  ],
                ),
              );
              if (ok != true || !context.mounted) return;
              try {
                final msg = await repo.cancelCredit(grant.id, 'Cancelled by owner');
                if (context.mounted) showSnack(context, msg);
                await onChanged();
              } on ApiException catch (e) {
                if (context.mounted) showSnack(context, e.message, error: true);
              }
            }
          : null,
    );
  }
}

/// Issue store credit to a trusted customer and push it to their WhatsApp.
class IssueCreditSheet extends StatefulWidget {
  const IssueCreditSheet({super.key, required this.repo, required this.customer});

  final Repo repo;
  final Customer customer;

  @override
  State<IssueCreditSheet> createState() => _IssueCreditSheetState();
}

class _IssueCreditSheetState extends State<IssueCreditSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  bool _sendWhatsApp = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Enter the credit amount');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final res = await widget.repo.issueCredit({
        'customerId': widget.customer.id,
        'amount': amount,
        'reason': _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        'sendWhatsApp': _sendWhatsApp,
      });
      if (!mounted) return;
      showSnack(context, res.message);

      final link = (res.data as Map<String, dynamic>)['whatsAppLink'] as String?;
      if (_sendWhatsApp && link != null) await openWhatsApp(context, link);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final headroom = c.creditLimit - c.creditBalance;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Give credit',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${c.name}  -  +91 ${c.mobile}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            if (c.creditLimit > 0)
              Text(
                'Limit ${money(c.creditLimit)}  -  unclaimed ${money(c.creditBalance)}'
                '  -  can give up to ${money(headroom < 0 ? 0 : headroom)}',
                style: const TextStyle(fontSize: 12),
              ),
            const SizedBox(height: 18),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Credit amount',
                prefixText: '₹ ',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'Festival credit, loyalty bonus, refund...',
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _sendWhatsApp,
              onChanged: (v) => setState(() => _sendWhatsApp = v),
              title: const Text('Tell the customer on WhatsApp'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? CoinLoader(size: 22)
                  : const Text('Give credit'),
            ),
          ],
        ),
      ),
    );
  }
}

