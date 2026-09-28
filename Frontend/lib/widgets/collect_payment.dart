import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../models/proof_models.dart';
import 'upi_qr.dart';

/// What the counter recorded when the money was taken.
class CollectedPayment {
  const CollectedPayment({this.note});

  /// Added to the bill's note, e.g. "UPI ref 426512345678" or "Card ****1234, auth 0931A2".
  final String? note;
}

/// The checkout step, like a supermarket or bar counter:
///  * UPI  - a big QR with the amount; the customer scans it with GPay/PhonePe/
///           Paytm and the cashier confirms once the money shows up.
///  * Card - charge the amount on the shop's card machine (POS terminal) and
///           note the last 4 digits / approval code.
///  * Cash - type what the customer handed over and see the change to return.
/// Returns null when the cashier cancels, so the bill is not saved.
Future<CollectedPayment?> collectPayment(
  BuildContext context, {
  required String mode,
  required double amount,
  ShopUpi? upi,
  String? billLabel,
}) {
  final Widget body = switch (mode) {
    'UPI' => _UpiCollect(amount: amount, upi: upi, billLabel: billLabel),
    'Card' => _CardCollect(amount: amount),
    _ => _CashCollect(amount: amount),
  };
  return showDialog<CollectedPayment>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: body,
        ),
      ),
    ),
  );
}

Widget _title(BuildContext context, IconData icon, Color color, String title, double amount) {
  return Column(
    children: [
      CircleAvatar(
        radius: 26,
        backgroundColor: color.withValues(alpha: 0.14),
        child: Icon(icon, color: color, size: 28),
      ),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(money(amount),
          style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: color)),
    ],
  );
}

Widget _buttons(BuildContext context,
    {required String okLabel, required VoidCallback onOk, Color? okColor}) {
  return Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        flex: 2,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: okColor),
          onPressed: onOk,
          icon: const Icon(Icons.check),
          label: Text(okLabel),
        ),
      ),
    ],
  );
}

// ---------------------------------------------------------------- UPI

class _UpiCollect extends StatefulWidget {
  const _UpiCollect({required this.amount, this.upi, this.billLabel});
  final double amount;
  final ShopUpi? upi;
  final String? billLabel;

  @override
  State<_UpiCollect> createState() => _UpiCollectState();
}

class _UpiCollectState extends State<_UpiCollect> {
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF0F5C43);
    final scheme = Theme.of(context).colorScheme;
    final upi = widget.upi;
    final ready = upi?.isSetUp == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, Icons.qr_code_2, green, 'Collect by UPI', widget.amount),
        const SizedBox(height: 14),
        if (ready) ...[
          UpiQrCard(upi: upi!, amount: widget.amount, note: widget.billLabel, size: 240),
          const SizedBox(height: 6),
          Text(
            'Turn the screen to the customer. They scan with Google Pay, PhonePe, Paytm '
            'or any bank app - the amount is already filled in.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ] else
          Card(
            color: scheme.tertiaryContainer.withValues(alpha: 0.5),
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Your UPI ID is not set up'),
              subtitle: Text('Add it under Menu -> UPI payment QR to show a QR with the '
                  'amount here. You can still confirm a UPI payment taken another way.'),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _ref,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: 'UPI reference (optional)',
            hintText: '12-digit UTR from the customer\'s screen',
            prefixIcon: Icon(Icons.tag),
          ),
        ),
        const SizedBox(height: 6),
        Text('Check the money has reached your bank / UPI app before confirming.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline)),
        const SizedBox(height: 14),
        _buttons(
          context,
          okLabel: 'Payment received',
          okColor: green,
          onOk: () => Navigator.pop(
            context,
            CollectedPayment(
                note: _ref.text.trim().isEmpty ? 'Paid by UPI' : 'UPI ref ${_ref.text.trim()}'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Card

class _CardCollect extends StatefulWidget {
  const _CardCollect({required this.amount});
  final double amount;

  @override
  State<_CardCollect> createState() => _CardCollectState();
}

class _CardCollectState extends State<_CardCollect> {
  final _last4 = TextEditingController();
  final _auth = TextEditingController();

  @override
  void dispose() {
    _last4.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const indigo = Color(0xFF3949AB);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, Icons.credit_card, indigo, 'Card payment', widget.amount),
        const SizedBox(height: 14),
        Card(
          color: indigo.withValues(alpha: 0.07),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StepLine('1', 'Enter the amount on your card machine (POS / swipe terminal)'),
                _StepLine('2', 'Customer taps, inserts or swipes the card and enters the PIN'),
                _StepLine('3', 'When the machine prints "APPROVED", confirm here'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _last4,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Card last 4',
                  hintText: '1234',
                  prefixText: '**** ',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _auth,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'Approval code',
                  hintText: 'On the slip',
                ),
              ),
            ),
          ],
        ),
        Text('Both optional - they help match the bill to the card slip later.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline)),
        const SizedBox(height: 14),
        _buttons(
          context,
          okLabel: 'Card approved',
          okColor: indigo,
          onOk: () {
            final parts = [
              if (_last4.text.trim().isNotEmpty) 'Card ****${_last4.text.trim()}',
              if (_auth.text.trim().isNotEmpty) 'auth ${_auth.text.trim()}',
            ];
            Navigator.pop(
                context, CollectedPayment(note: parts.isEmpty ? 'Paid by card' : parts.join(', ')));
          },
        ),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  const _StepLine(this.n, this.text);
  final String n;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n.  ', style: const TextStyle(fontWeight: FontWeight.w800)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

// ---------------------------------------------------------------- Cash

class _CashCollect extends StatefulWidget {
  const _CashCollect({required this.amount});
  final double amount;

  @override
  State<_CashCollect> createState() => _CashCollectState();
}

class _CashCollectState extends State<_CashCollect> {
  final _given = TextEditingController();

  @override
  void dispose() {
    _given.dispose();
    super.dispose();
  }

  double get _givenValue => double.tryParse(_given.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1B7F3B);
    final scheme = Theme.of(context).colorScheme;
    final change = _givenValue - widget.amount;

    // Common notes customers hand over, rounded up from the bill.
    final suggestions = <double>{
      for (final note in [10, 20, 50, 100, 200, 500, 2000])
        ((widget.amount / note).ceil() * note).toDouble(),
    }.where((v) => v >= widget.amount).toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _title(context, Icons.payments_outlined, green, 'Cash payment', widget.amount),
        const SizedBox(height: 14),
        TextField(
          controller: _given,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Cash received from customer',
            prefixText: '₹ ',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in suggestions.take(4))
              ActionChip(
                label: Text(money(s)),
                onPressed: () => setState(() => _given.text = s.toStringAsFixed(0)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (_givenValue > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: change >= 0 ? green.withValues(alpha: 0.1) : scheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(change >= 0 ? 'Return change' : 'Still short',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(money(change.abs()),
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: change >= 0 ? green : scheme.error)),
              ],
            ),
          ),
        const SizedBox(height: 14),
        _buttons(
          context,
          okLabel: 'Cash received',
          okColor: green,
          onOk: () {
            if (_givenValue > 0 && change < -0.009) return;
            Navigator.pop(
              context,
              CollectedPayment(
                note: _givenValue > 0 && change > 0.009
                    ? 'Cash ${money(_givenValue)}, change ${money(change)}'
                    : null,
              ),
            );
          },
        ),
      ],
    );
  }
}
