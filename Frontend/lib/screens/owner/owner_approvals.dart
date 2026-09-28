import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/proof_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

/// UPI screenshots customers have sent. Approving one records the payment and
/// re-issues the bill showing what is still owed.
class PaymentApprovalsScreen extends StatefulWidget {
  const PaymentApprovalsScreen({super.key, required this.repo});

  final Repo repo;

  @override
  State<PaymentApprovalsScreen> createState() => _PaymentApprovalsScreenState();
}

class _PaymentApprovalsScreenState extends State<PaymentApprovalsScreen> {
  String? _status = 'Pending';
  late Future<List<PaymentProof>> _future = widget.repo.paymentProofs(status: 'Pending');
  bool _changed = false;

  Future<void> _reload() async {
    setState(() => _future = widget.repo.paymentProofs(status: _status));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _process(PaymentProof proof, bool approve) async {
    String? remarks;
    if (!approve) {
      final controller = TextEditingController();
      remarks = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reject this payment?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The customer is told and can send it again. Nothing changes in '
                'their balance.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Reason', hintText: 'Reference not found'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
              child: const Text('Reject'),
            ),
          ],
        ),
      );
      if (remarks == null) return;
    }

    try {
      final res = await widget.repo.processProof(proof.id, approve, remarks);
      if (!mounted) return;
      showSnack(context, res.message);
      _changed = true;

      if (approve) {
        final data = ProofApprovalResult.fromJson(res.data as Map<String, dynamic>);
        if (data.whatsAppLink != null && mounted) {
          await openWhatsApp(context, data.whatsAppLink);
        }
      }
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Customer payments')),
        body: Column(
          children: [
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                children: [
                  for (final s in const ['Pending', 'Approved', 'Rejected', null])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(s ?? 'All'),
                        selected: _status == s,
                        onSelected: (_) {
                          setState(() => _status = s);
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: AsyncBody<List<PaymentProof>>(
                future: _future,
                onRefresh: _reload,
                builder: (context, list) {
                  if (list.isEmpty) {
                    return ListView(
                      children: [
                        const SizedBox(height: 100),
                        EmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: _status == 'Pending'
                              ? 'Nothing waiting'
                              : 'No payments here',
                          subtitle: _status == 'Pending'
                              ? 'UPI screenshots your customers send will appear here'
                              : null,
                        ),
                      ],
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _ProofCard(
                      proof: list[i],
                      repo: widget.repo,
                      onApprove: () => _process(list[i], true),
                      onReject: () => _process(list[i], false),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProofCard extends StatelessWidget {
  const _ProofCard({
    required this.proof,
    required this.repo,
    required this.onApprove,
    required this.onReject,
  });

  final PaymentProof proof;
  final Repo repo;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(proof.customerName,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      Text('+91 ${proof.customerMobile}  -  ${relative(proof.submittedAt)}',
                          style: TextStyle(
                              fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(proof.amount),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    StatusPill(proof.status),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),

            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.account_balance_wallet_outlined, size: 15),
                  label: Text(proof.method),
                ),
                if (proof.invoiceNumber != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.receipt_long_outlined, size: 15),
                    label: Text(proof.invoiceNumber!),
                  ),
                if ((proof.referenceNo ?? '').isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.tag, size: 15),
                    label: Text(proof.referenceNo!),
                  ),
              ],
            ),

            if ((proof.note ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('"${proof.note}"',
                    style: const TextStyle(
                        fontSize: 13, fontStyle: FontStyle.italic)),
              ),

            if (proof.hasScreenshot) ...[
              const SizedBox(height: 12),
              _ScreenshotView(proofId: proof.id, repo: repo),
            ],

            if (proof.isPending) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_outlined, size: 18, color: scheme.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Check your bank / UPI app for ${money(proof.amount)}'
                        '${(proof.referenceNo ?? '').isEmpty ? '' : ' with ref ${proof.referenceNo}'}'
                        ' before approving.',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  proof.invoiceNumber != null
                      ? 'Approving leaves ${money(proof.invoiceBalance - proof.amount)} '
                          'on ${proof.invoiceNumber} and sends the updated bill.'
                      : 'Approving settles ${money(proof.amount)} against their oldest bills.',
                  style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onReject, child: const Text('Reject')),
                  const SizedBox(width: 6),
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Approve'),
                    style: FilledButton.styleFrom(minimumSize: const Size(130, 42)),
                  ),
                ],
              ),
            ] else if ((proof.remarks ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Note: ${proof.remarks}',
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Loads the screenshot with the bearer token attached, which Image.network
/// cannot do on web.
class _ScreenshotView extends StatefulWidget {
  const _ScreenshotView({required this.proofId, required this.repo});

  final int proofId;
  final Repo repo;

  @override
  State<_ScreenshotView> createState() => _ScreenshotViewState();
}

class _ScreenshotViewState extends State<_ScreenshotView> {
  late final Future<Uint8List> _future = widget.repo.proofImage(widget.proofId);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const CoinLoader(),
          );
        }
        if (snap.hasError || snap.data == null) {
          return Container(
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('Screenshot unavailable',
                style: TextStyle(fontSize: 12.5, color: scheme.outline)),
          );
        }

        final bytes = snap.data!;
        return GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InteractiveViewer(
                    maxScale: 5,
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220, minWidth: double.infinity),
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Tap to zoom',
                          style: TextStyle(fontSize: 11, color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

