import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/branding_image.dart';
import '../../widgets/common.dart';
import '../../widgets/invoice_actions.dart';

class BillDetailScreen extends StatefulWidget {
  const BillDetailScreen({
    super.key,
    required this.repo,
    required this.invoiceId,
    this.customerView = false,
    this.justCreated = false,
    this.staffView = false,
  });

  final Repo repo;
  final int invoiceId;

  /// Customers get a read-only version of the same layout.
  final bool customerView;

  /// Shows a "bill saved" banner when arriving straight from New bill.
  final bool justCreated;

  /// A worker looking at their own bill: everything but Cancel.
  final bool staffView;

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  late Future<Invoice> _future = _load();

  Future<Invoice> _load() => widget.customerView
      ? widget.repo.myBill(widget.invoiceId)
      : widget.repo.invoice(widget.invoiceId);

  Future<void> _reload() async {
    setState(() => _future = _load());
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _cancel() async {
    final reason = await _askReason(context);
    if (reason == null) return;
    try {
      final msg = await widget.repo.cancelInvoice(widget.invoiceId, reason);
      if (!mounted) return;
      showSnack(context, msg);
      await _reload();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Invoice>(
      future: _future,
      builder: (context, snap) {
        final inv = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(inv?.invoiceNumber ?? 'Bill'),
            actions: [
              if (!widget.customerView && !widget.staffView && inv != null && !inv.isCancelled)
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'cancel') _cancel();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'cancel',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.cancel_outlined),
                        title: Text('Cancel bill'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          bottomNavigationBar: inv == null
              ? null
              : InvoiceActionBar(
                  invoice: inv,
                  repo: widget.customerView ? null : widget.repo,
                  allowWhatsApp: !widget.customerView,
                ),
          body: AsyncBody<Invoice>(
            future: _future,
            onRefresh: _reload,
            builder: (context, inv) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ResponsiveCenter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.justCreated) const _SavedBanner(),
                      if (inv.isCancelled) const _CancelledBanner(),
                      InvoiceCard(invoice: inv, customerView: widget.customerView),
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

/// The bill laid out like a printed invoice: letterhead, bill-to, items, totals.
class InvoiceCard extends StatelessWidget {
  const InvoiceCard({super.key, required this.invoice, this.customerView = false});

  final Invoice invoice;
  final bool customerView;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ------------------------------------------------ letterhead
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primaryContainer,
                  scheme.primaryContainer.withValues(alpha: 0.55),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((inv.logoUrl ?? '').isNotEmpty) ...[
                  BrandingImage(url: inv.logoUrl, width: 54, height: 54),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inv.businessName,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: scheme.onPrimaryContainer)),
                      if ((inv.businessAddress ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(inv.businessAddress!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
                        ),
                      if ((inv.businessGstNumber ?? '').isNotEmpty)
                        Text('GSTIN ${inv.businessGstNumber}',
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                StatusPill(inv.status),
              ],
            ),
          ),

          // ------------------------------------------------ meta
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BILL TO', style: muted.copyWith(fontSize: 11, letterSpacing: 0.6)),
                      const SizedBox(height: 3),
                      Text(inv.customerName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      Text('+91 ${inv.customerMobile}', style: muted),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('INVOICE', style: muted.copyWith(fontSize: 11, letterSpacing: 0.6)),
                    const SizedBox(height: 3),
                    Text(inv.invoiceNumber,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(dateTimeOf(inv.invoiceDate), style: muted.copyWith(fontSize: 11.5)),
                  ],
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Divider(height: 1),
          ),

          // ------------------------------------------------ items
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                for (var i = 0; i < inv.items.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(right: 10, top: 1),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(inv.items[i].productName,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(
                                '${qty(inv.items[i].quantity)} x ${money(inv.items[i].unitPrice)}'
                                '${inv.items[i].taxPercent > 0 ? '  +${qty(inv.items[i].taxPercent)}% GST' : ''}',
                                style: muted,
                              ),
                            ],
                          ),
                        ),
                        Text(money(inv.items[i].lineTotal),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ------------------------------------------------ totals
          Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                MoneyRow('Sub total', inv.subTotal),
                if (inv.discountAmount > 0) MoneyRow('Discount', -inv.discountAmount),
                if (inv.taxAmount > 0) MoneyRow('GST', inv.taxAmount),
                const Divider(height: 18),
                MoneyRow('Total', inv.grandTotal, bold: true),
                MoneyRow(
                    inv.paidAmount > 0 ? 'Paid (${inv.paymentMode})' : 'Paid',
                    inv.paidAmount,
                    tone: moneyPositive(context)),
                if (inv.balanceAmount > 0)
                  MoneyRow('Balance / Udhaar', inv.balanceAmount,
                      bold: true, tone: moneyNegative(context)),
                if (inv.tenders.length > 1 || inv.tenders.any((t) => t.mode == 'Card')) ...[
                  const Divider(height: 18),
                  for (final t in inv.tenders)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Icon(
                              t.mode == 'Card'
                                  ? (t.isInternational ? Icons.public : Icons.credit_card)
                                  : t.mode == 'UPI'
                                      ? Icons.qr_code_2
                                      : Icons.payments_outlined,
                              size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              t.label +
                                  ((t.cardApprovalCode ?? '').isNotEmpty ? '  ·  auth ${t.cardApprovalCode}' : ''),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          Text(money(t.amount), style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                ],
                if ((inv.changeReturned ?? 0) > 0)
                  MoneyRow('Cash given ${money(inv.cashTendered)} · change', inv.changeReturned!),
              ],
            ),
          ),

          if (!customerView && (inv.billedByName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  const Icon(Icons.badge_outlined, size: 16),
                  const SizedBox(width: 6),
                  Text('Billed by ${inv.billedByName}', style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),

          if (!customerView &&
              !inv.isCancelled &&
              inv.customerOutstanding > inv.balanceAmount + 0.009)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: moneyWarning(context)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Customer owes ${money(inv.customerOutstanding)} in total across all bills.',
                      style: TextStyle(fontSize: 12.5, color: moneyWarning(context)),
                    ),
                  ),
                ],
              ),
            ),

          if ((inv.notes ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              child: Text('Note: ${inv.notes}', style: muted),
            ),
        ],
      ),
    );
  }
}

class _SavedBanner extends StatelessWidget {
  const _SavedBanner();

  @override
  Widget build(BuildContext context) {
    final c = moneyPositive(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: c),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Bill saved. Send it on WhatsApp, share the PDF or print it below.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _CancelledBanner extends StatelessWidget {
  const _CancelledBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.block),
          SizedBox(width: 10),
          Expanded(
            child: Text('This bill was cancelled. Stock and Udhaar were reversed.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

Future<String?> _askReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Cancel this bill?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Stock goes back to inventory and the customer\'s Udhaar is reversed. '
            'The bill stays in history as cancelled.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep bill')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
          child: const Text('Cancel bill'),
        ),
      ],
    ),
  );
}
