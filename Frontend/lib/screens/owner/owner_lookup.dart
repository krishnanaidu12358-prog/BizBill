import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/admin_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'owner_customer_detail.dart';

/// Type a mobile number, see how that customer behaves across BizBill before
/// deciding whether to give them Udhaar.
class CustomerLookupScreen extends StatefulWidget {
  const CustomerLookupScreen({super.key, required this.repo});

  final Repo repo;

  @override
  State<CustomerLookupScreen> createState() => _CustomerLookupScreenState();
}

class _CustomerLookupScreenState extends State<CustomerLookupScreen> {
  final _mobile = TextEditingController();
  CustomerInsight? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final m = _mobile.text.trim();
    if (m.length != 10) {
      setState(() => _error = 'Enter a 10-digit mobile number.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final r = await widget.repo.lookupCustomer(m);
      setState(() => _result = r);
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _result = null;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Check a customer')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Enter a mobile number to see that customer\'s payment record across '
            'every shop on BizBill.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _mobile,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Customer mobile number',
              prefixText: '+91  ',
              counterText: '',
              errorText: _error,
              prefixIcon: const Icon(Icons.phone_android),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _search,
            icon: _busy
                ? CoinLoader(size: 20)
                : const Icon(Icons.search),
            label: Text(_busy ? 'Checking...' : 'Check customer'),
          ),

          if (_result != null) ...[
            const SizedBox(height: 24),
            if (!_result!.found)
              const EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No record yet',
                subtitle:
                    'No shop on BizBill has billed this number. Treat them as a new customer.',
              )
            else
              _InsightCard(insight: _result!, repo: widget.repo),
          ],
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.repo});

  final CustomerInsight insight;
  final Repo repo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signalTone = statusColor(insight.paymentSignal, scheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      child: Text(
                        insight.name.isEmpty ? '?' : insight.name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 19),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(insight.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('+91 ${insight.mobile}',
                              style: TextStyle(
                                  fontSize: 13, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // --- the rating -------------------------------------------
                if (insight.rating != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(insight.rating!.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 40, fontWeight: FontWeight.w800, height: 1)),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              for (var i = 1; i <= 5; i++)
                                Icon(
                                  insight.rating! >= i
                                      ? Icons.star
                                      : insight.rating! >= i - 0.5
                                          ? Icons.star_half
                                          : Icons.star_border,
                                  size: 18,
                                  color: moneyWarning(context),
                                ),
                            ],
                          ),
                          Text(insight.ratingLabel,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ] else
                  Row(
                    children: [
                      const Icon(Icons.fiber_new_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(insight.ratingLabel,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ],
                  ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _Fact(
                          label: 'Shops',
                          value: '${insight.shopCount}',
                          icon: Icons.storefront_outlined),
                    ),
                    Expanded(
                      child: _Fact(
                          label: 'Bills',
                          value: '${insight.totalBills}',
                          icon: Icons.receipt_long_outlined),
                    ),
                    Expanded(
                      child: _Fact(
                        label: 'Payments',
                        value: insight.paymentSignal,
                        icon: Icons.schedule,
                        tone: signalTone,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(insight.summary,
                      style: const TextStyle(fontSize: 13, height: 1.4)),
                ),

                if (insight.hasOverdueElsewhere) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 18, color: moneyNegative(context)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This customer has a bill over 30 days unpaid at another shop.',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: moneyNegative(context)),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                Text(
                  'Amounts and names from other shops are never shown.',
                  style: TextStyle(fontSize: 11.5, color: scheme.outline),
                ),
              ],
            ),
          ),
        ),

        // --- what this shop itself knows -----------------------------------
        const SizedBox(height: 14),
        if (insight.thisShop != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('At your shop',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  MoneyRow('They owe you', insight.thisShop!.outstandingBalance,
                      tone: insight.thisShop!.outstandingBalance > 0
                          ? moneyNegative(context)
                          : null),
                  MoneyRow('Credit you gave', insight.thisShop!.creditBalance),
                  if (insight.thisShop!.isTrusted)
                    MoneyRow('Credit limit', insight.thisShop!.creditLimit),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Chip(
                        avatar: Icon(
                          insight.thisShop!.isTrusted
                              ? Icons.verified
                              : Icons.help_outline,
                          size: 16,
                          color: insight.thisShop!.isTrusted
                              ? moneyPositive(context)
                              : null,
                        ),
                        label: Text(insight.thisShop!.isTrusted
                            ? 'Trusted'
                            : 'Not trusted'),
                      ),
                      const SizedBox(width: 8),
                      Chip(label: Text('${insight.thisShop!.billCount} bills')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerDetailScreen(
                            repo: repo,
                            customerId: insight.thisShop!.customerId,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open customer'),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This number is not one of your customers yet. '
                      'Add them from the Customers tab to start billing.',
                      style: TextStyle(
                          fontSize: 13, height: 1.4, color: scheme.onSurfaceVariant),
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

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 18, color: tone ?? scheme.onSurfaceVariant),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: tone)),
        ),
        Text(label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

