import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

class CustomerCreditsTab extends StatefulWidget {
  const CustomerCreditsTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<CustomerCreditsTab> createState() => _CustomerCreditsTabState();
}

class _CustomerCreditsTabState extends State<CustomerCreditsTab> {
  late Future<_Bundle> _future = _load();

  Future<_Bundle> _load() async {
    final results = await Future.wait([
      widget.repo.myCredits(),
      widget.repo.myClaims(),
    ]);
    return _Bundle(
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

  Future<void> _claim(CreditGrant g) async {
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => _ClaimDialog(grant: g),
    );
    if (amount == null) return;

    try {
      final msg = await widget.repo.claimCredit(g.id, amount, null);
      if (!mounted) return;
      showSnack(context, msg);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _cancelClaim(CreditClaim c) async {
    try {
      final msg = await widget.repo.cancelMyClaim(c.id);
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

    return AsyncBody<_Bundle>(
      future: _future,
      onRefresh: _reload,
      builder: (context, b) {
        final claimable = b.grants.where((g) => g.isClaimable).toList();
        final others = b.grants.where((g) => !g.isClaimable).toList();
        final pending = b.claims.where((c) => c.status == 'Pending').toList();
        final past = b.claims.where((c) => c.status != 'Pending').toList();

        if (b.grants.isEmpty && b.claims.isEmpty) {
          return ListView(
            children: const [
              SizedBox(height: 120),
              EmptyState(
                icon: Icons.card_giftcard,
                title: 'No credits yet',
                subtitle:
                    'When a shop gives you credit, it appears here and you can claim it',
              ),
            ],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (claimable.isNotEmpty) ...[
              const Text('Ready to claim',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              for (final g in claimable)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(g.businessName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15)),
                              ),
                              Text(money(g.balanceAmount),
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 19,
                                      color: moneyPositive(context))),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${g.creditCode}'
                            '${(g.reason ?? '').isEmpty ? '' : '  -  ${g.reason}'}',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          if (g.expiryDate != null)
                            Text('Valid till ${dateOf(g.expiryDate)}',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.onSurfaceVariant)),
                          if (g.claimedAmount > 0)
                            Text('Already claimed ${money(g.claimedAmount)}',
                                style: TextStyle(
                                    fontSize: 12, color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              FilledButton.icon(
                                onPressed: () => _claim(g),
                                icon: const Icon(Icons.redeem, size: 18),
                                label: const Text('Claim'),
                                style: FilledButton.styleFrom(
                                    minimumSize: const Size(130, 42)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],

            if (pending.isNotEmpty) ...[
              const Text('Waiting for approval',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < pending.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.hourglass_top),
                        title: Text(money(pending[i].amount),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${pending[i].businessName}  -  ${relative(pending[i].requestedAt)}'),
                        trailing: TextButton(
                          onPressed: () => _cancelClaim(pending[i]),
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (others.isNotEmpty) ...[
              const Text('Used and expired credits',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < others.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(others[i].businessName),
                        subtitle: Text(
                            '${others[i].creditCode}  -  ${dateOf(others[i].createdAt)}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(money(others[i].amount),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13)),
                            const SizedBox(height: 2),
                            StatusPill(others[i].status),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            if (past.isNotEmpty) ...[
              const Text('Claim history',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < past.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(money(past[i].amount),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            '${past[i].businessName}  -  ${relative(past[i].requestedAt)}'
                            '${(past[i].remarks ?? '').isEmpty ? '' : '\n${past[i].remarks}'}'),
                        isThreeLine: (past[i].remarks ?? '').isNotEmpty,
                        trailing: StatusPill(past[i].status),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Bundle {
  _Bundle(this.grants, this.claims);
  final List<CreditGrant> grants;
  final List<CreditClaim> claims;
}

class _ClaimDialog extends StatefulWidget {
  const _ClaimDialog({required this.grant});

  final CreditGrant grant;

  @override
  State<_ClaimDialog> createState() => _ClaimDialogState();
}

class _ClaimDialogState extends State<_ClaimDialog> {
  late final _controller =
      TextEditingController(text: widget.grant.balanceAmount.toStringAsFixed(2));
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
    if (v > widget.grant.balanceAmount) {
      setState(() =>
          _error = 'Only ${money(widget.grant.balanceAmount)} is available');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Claim credit'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.grant.businessName}\n'
            'Available ${money(widget.grant.balanceAmount)}',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount to claim',
              prefixText: '₹ ',
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          const Text(
            'The shop will approve it, then the amount is taken off what you owe.',
            style: TextStyle(fontSize: 12, height: 1.35),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(120, 40)),
          child: const Text('Send claim'),
        ),
      ],
    );
  }
}

