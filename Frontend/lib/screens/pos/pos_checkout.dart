import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../models/proof_models.dart';
import '../../widgets/upi_qr.dart';

/// One payment taken at the counter, before the bill is saved.
class TenderDraft {
  TenderDraft({
    required this.mode,
    required this.amount,
    this.referenceNo,
    this.cardScope,
    this.cardNetwork,
    this.cardType,
    this.cardLast4,
    this.cardApprovalCode,
  });

  final String mode;
  final double amount;
  final String? referenceNo;
  final String? cardScope;
  final String? cardNetwork;
  final String? cardType;
  final String? cardLast4;
  final String? cardApprovalCode;

  bool get isCard => mode == 'Card';

  String get label {
    if (isCard) {
      final bits = [
        cardScope == 'International' ? 'Intl card' : 'Card',
        if ((cardNetwork ?? '').isNotEmpty) cardNetwork!,
        if ((cardLast4 ?? '').isNotEmpty) '****$cardLast4',
      ];
      return bits.join(' ');
    }
    if (mode == 'UPI') return (referenceNo ?? '').isEmpty ? 'UPI' : 'UPI ref $referenceNo';
    return mode;
  }

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'amount': double.parse(amount.toStringAsFixed(2)),
        if ((referenceNo ?? '').isNotEmpty) 'referenceNo': referenceNo,
        if (isCard)
          'card': {
            'scope': cardScope ?? 'Domestic',
            if ((cardNetwork ?? '').isNotEmpty) 'network': cardNetwork,
            if ((cardType ?? '').isNotEmpty) 'type': cardType,
            if ((cardLast4 ?? '').isNotEmpty) 'last4': cardLast4,
            if ((cardApprovalCode ?? '').isNotEmpty) 'approvalCode': cardApprovalCode,
          },
      };
}

class CheckoutResult {
  const CheckoutResult({required this.tenders, this.cashTendered, this.leaveAsUdhaar = 0});

  final List<TenderDraft> tenders;

  /// Total cash the customer handed over (for the change line).
  final double? cashTendered;

  /// Balance left unpaid on purpose (trusted customers only).
  final double leaveAsUdhaar;

  double get paid => tenders.fold(0.0, (s, t) => s + t.amount);
  double get change {
    final cash = tenders.where((t) => t.mode == 'Cash').fold(0.0, (s, t) => s + t.amount);
    final given = cashTendered ?? 0;
    return given > cash ? given - cash : 0;
  }
}

/// Supermarket-style checkout: take cash (with change), show the UPI QR with
/// the amount, or charge a domestic / international card on the card machine.
/// Several payments can be combined (e.g. part cash, part card).
Future<CheckoutResult?> showPosCheckout(
  BuildContext context, {
  required double total,
  required String initialMode,
  ShopUpi? upi,
  String? billLabel,
  bool allowUdhaar = false,
  String? customerName,
}) {
  return showDialog<CheckoutResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 820),
        child: _Checkout(
          total: total,
          initialMode: initialMode,
          upi: upi,
          billLabel: billLabel,
          allowUdhaar: allowUdhaar,
          customerName: customerName,
        ),
      ),
    ),
  );
}

class _Checkout extends StatefulWidget {
  const _Checkout({
    required this.total,
    required this.initialMode,
    this.upi,
    this.billLabel,
    this.allowUdhaar = false,
    this.customerName,
  });

  final double total;
  final String initialMode;
  final ShopUpi? upi;
  final String? billLabel;
  final bool allowUdhaar;
  final String? customerName;

  @override
  State<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<_Checkout> {
  late String _mode = widget.initialMode;
  final List<TenderDraft> _tenders = [];
  double _cashGiven = 0;

  final _cash = TextEditingController();
  final _amount = TextEditingController();
  final _upiRef = TextEditingController();
  final _last4 = TextEditingController();
  final _auth = TextEditingController();
  final _cashFocus = FocusNode();

  String _scope = 'Domestic';
  String? _network;
  String? _cardType;

  static const _domesticNetworks = ['RuPay', 'Visa', 'Mastercard', 'Amex', 'Diners', 'Maestro', 'Other'];
  static const _intlNetworks = ['Visa', 'Mastercard', 'Amex', 'Diners', 'Discover', 'JCB', 'UnionPay', 'Other'];

  double get _paid => _tenders.fold(0.0, (s, t) => s + t.amount);
  double get _remaining => double.parse((widget.total - _paid).clamp(0, double.infinity).toStringAsFixed(2));

  @override
  void initState() {
    super.initState();
    _resetAmount();
  }

  @override
  void dispose() {
    _cash.dispose();
    _amount.dispose();
    _upiRef.dispose();
    _last4.dispose();
    _auth.dispose();
    _cashFocus.dispose();
    super.dispose();
  }

  void _resetAmount() => _amount.text = _remaining.toStringAsFixed(2);

  void _setMode(String m) {
    setState(() {
      _mode = m;
      _resetAmount();
    });
    if (m == 'Cash') _cashFocus.requestFocus();
  }

  /// Adds a payment; closes the checkout as soon as the bill is covered.
  void _add(TenderDraft t) {
    if (t.amount <= 0) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tenders.add(t);
      _cash.clear();
      _upiRef.clear();
      _last4.clear();
      _auth.clear();
      _network = null;
      _cardType = null;
      _resetAmount();
    });
    if (_remaining <= 0.009) _finish();
  }

  void _finish({double leave = 0}) {
    Navigator.pop(
      context,
      CheckoutResult(
        tenders: List.of(_tenders),
        cashTendered: _cashGiven > 0 ? _cashGiven : null,
        leaveAsUdhaar: leave,
      ),
    );
  }

  double _amountValue() {
    final v = double.tryParse(_amount.text.trim()) ?? 0;
    return v.clamp(0, _remaining).toDouble();
  }

  void _takeCash() {
    final given = double.tryParse(_cash.text.trim()) ?? 0;
    if (given <= 0) {
      // Exact cash - the common case at a busy counter.
      _cashGiven += _remaining;
      _add(TenderDraft(mode: 'Cash', amount: _remaining));
      return;
    }
    final applied = given >= _remaining ? _remaining : given;
    _cashGiven += given;
    _add(TenderDraft(mode: 'Cash', amount: applied));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final remaining = _remaining;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // --------------------------------------------------------- header
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.customerName == null ? 'Checkout' : 'Checkout - ${widget.customerName}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(money(widget.total),
                        style: TextStyle(
                            fontSize: 30, fontWeight: FontWeight.w800, color: scheme.primary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Still to pay', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  Text(money(remaining),
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: remaining > 0 ? scheme.error : const Color(0xFF1B7F3B))),
                ],
              ),
              IconButton(
                tooltip: 'Back to the bill',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),

        // -------------------------------------------------------- tenders
        if (_tenders.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (var i = 0; i < _tenders.length; i++)
                  InputChip(
                    avatar: Icon(_iconFor(_tenders[i].mode), size: 18),
                    label: Text('${_tenders[i].label}  ${money(_tenders[i].amount)}'),
                    onDeleted: () => setState(() {
                      final t = _tenders.removeAt(i);
                      if (t.mode == 'Cash') _cashGiven = 0;
                      _resetAmount();
                    }),
                  ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Cash', icon: Icon(Icons.payments_outlined), label: Text('Cash')),
              ButtonSegment(value: 'UPI', icon: Icon(Icons.qr_code_2), label: Text('UPI QR')),
              ButtonSegment(value: 'Card', icon: Icon(Icons.credit_card), label: Text('Card')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => _setMode(s.first),
          ),
        ),

        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: switch (_mode) {
              'UPI' => _upiPanel(context),
              'Card' => _cardPanel(context),
              _ => _cashPanel(context),
            },
          ),
        ),

        if (widget.allowUdhaar && remaining > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextButton.icon(
              onPressed: () => _finish(leave: remaining),
              icon: const Icon(Icons.schedule),
              label: Text('Leave ${money(remaining)} as Udhaar'),
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(String mode) => switch (mode) {
        'UPI' => Icons.qr_code_2,
        'Card' => Icons.credit_card,
        _ => Icons.payments_outlined,
      };

  // ------------------------------------------------------------------ cash

  Widget _cashPanel(BuildContext context) {
    const green = Color(0xFF1B7F3B);
    final scheme = Theme.of(context).colorScheme;
    final remaining = _remaining;
    final given = double.tryParse(_cash.text.trim()) ?? 0;
    final change = given - remaining;

    final suggestions = <double>{
      remaining.ceilToDouble(),
      for (final note in [50, 100, 200, 500, 2000]) ((remaining / note).ceil() * note).toDouble(),
    }.where((v) => v >= remaining && v > 0).toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cash,
          focusNode: _cashFocus,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _takeCash(),
          decoration: const InputDecoration(
            labelText: 'Cash received (leave empty for exact amount)',
            prefixText: '₹ ',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final s in suggestions.take(5))
              ActionChip(
                label: Text(money(s)),
                onPressed: () => setState(() => _cash.text = s.toStringAsFixed(0)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (given > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: change >= 0 ? green.withValues(alpha: 0.1) : scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(change >= 0 ? 'Return change' : 'Rest by another method',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(money(change.abs()),
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: change >= 0 ? green : scheme.onTertiaryContainer)),
              ],
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: green, minimumSize: const Size.fromHeight(52)),
          onPressed: _takeCash,
          icon: const Icon(Icons.check),
          label: Text(given > 0 && given < remaining
              ? 'Take ${money(given)} cash (Enter)'
              : 'Cash received (Enter)'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- UPI

  Widget _upiPanel(BuildContext context) {
    const green = Color(0xFF0F5C43);
    final scheme = Theme.of(context).colorScheme;
    final upi = widget.upi;
    final amount = _amountValue();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AmountField(controller: _amount, max: _remaining, onChanged: () => setState(() {})),
        const SizedBox(height: 10),
        if (upi?.isSetUp == true) ...[
          Center(
            child: UpiQrCard(upi: upi!, amount: amount, note: widget.billLabel, size: 230),
          ),
          Text(
            'Turn the screen to the customer. They scan with Google Pay, PhonePe, Paytm or any '
            'bank app - the amount is already filled in.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ] else
          Card(
            color: scheme.tertiaryContainer.withValues(alpha: 0.5),
            child: const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Shop UPI ID is not set up'),
              subtitle: Text('The owner can add it under Menu -> UPI payment QR. You can still '
                  'record a UPI payment taken on the shop\'s own QR stand.'),
            ),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: _upiRef,
          keyboardType: TextInputType.number,
          maxLength: 12,
          decoration: const InputDecoration(
            labelText: 'UPI reference / UTR (optional)',
            prefixIcon: Icon(Icons.tag),
          ),
        ),
        Text('Check the money has reached the shop account before confirming.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.outline)),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: green, minimumSize: const Size.fromHeight(52)),
          onPressed: amount <= 0
              ? null
              : () => _add(TenderDraft(
                    mode: 'UPI',
                    amount: amount,
                    referenceNo: _upiRef.text.trim().isEmpty ? null : _upiRef.text.trim(),
                  )),
          icon: const Icon(Icons.check),
          label: Text('UPI payment of ${money(amount)} received'),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ card

  Widget _cardPanel(BuildContext context) {
    const indigo = Color(0xFF3949AB);
    final scheme = Theme.of(context).colorScheme;
    final amount = _amountValue();
    final intl = _scope == 'International';
    final networks = intl ? _intlNetworks : _domesticNetworks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AmountField(controller: _amount, max: _remaining, onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'Domestic', icon: Icon(Icons.flag_outlined), label: Text('Indian card')),
            ButtonSegment(
                value: 'International', icon: Icon(Icons.public), label: Text('International card')),
          ],
          selected: {_scope},
          onSelectionChanged: (s) => setState(() {
            _scope = s.first;
            if (_network != null && !(_scope == 'International' ? _intlNetworks : _domesticNetworks)
                .contains(_network)) {
              _network = null;
            }
          }),
        ),
        const SizedBox(height: 10),
        Text('Card network', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            for (final n in networks)
              ChoiceChip(
                label: Text(n),
                selected: _network == n,
                onSelected: (v) => setState(() => _network = v ? n : null),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final t in const ['Debit', 'Credit', 'Prepaid'])
              ChoiceChip(
                label: Text(t),
                selected: _cardType == t,
                onSelected: (v) => setState(() => _cardType = v ? t : null),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          color: indigo.withValues(alpha: 0.07),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _step('1', 'Enter ${money(amount)} on the card machine (POS terminal).'),
                _step('2', 'Customer taps, inserts or swipes the card and enters the PIN.'),
                if (intl)
                  _step('3',
                      'International card: charge in rupees. If the machine offers the customer\'s own '
                      'currency (DCC), let the customer choose. Check the name and signature for '
                      'cards without PIN.'),
                _step(intl ? '4' : '3', 'When the slip says APPROVED, confirm here.'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
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
                  prefixText: '**** ',
                  helperText: 'Never the full number',
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
                  helperText: 'From the slip',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: indigo, minimumSize: const Size.fromHeight(52)),
          onPressed: amount <= 0
              ? null
              : () {
                  final last4 = _last4.text.trim();
                  if (last4.isNotEmpty && last4.length != 4) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Card last 4 must be 4 digits.')));
                    return;
                  }
                  _add(TenderDraft(
                    mode: 'Card',
                    amount: amount,
                    cardScope: _scope,
                    cardNetwork: _network,
                    cardType: _cardType,
                    cardLast4: last4.isEmpty ? null : last4,
                    cardApprovalCode: _auth.text.trim().isEmpty ? null : _auth.text.trim(),
                  ));
                },
          icon: const Icon(Icons.check),
          label: Text('Card approved - ${money(amount)}'),
        ),
      ],
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n.  ', style: const TextStyle(fontWeight: FontWeight.w800)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );
}

/// Amount for this payment - defaults to what is still due; lower it to split.
class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.max, required this.onChanged});

  final TextEditingController controller;
  final double max;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: 'Amount on this payment',
        helperText: 'Lower it to split the bill (e.g. part cash, part card). Max ${money(max)}',
        prefixText: '₹ ',
      ),
    );
  }
}
