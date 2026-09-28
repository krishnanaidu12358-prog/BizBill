import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/proof_models.dart';
import '../../services/repo.dart';
import '../../widgets/barcode_scanner.dart';
import '../../widgets/common.dart';
import '../../widgets/upi_qr.dart';

/// Customer pays the shop straight into the shop's bank account:
///   1. the shop's UPI QR is shown, and "Pay with UPI app" opens Google Pay,
///      PhonePe, Paytm, BHIM ... with the shop and amount already filled in;
///   2. back in BizBill the customer confirms with the UPI reference number
///      (and a screenshot if they like), and the shop owner is told at once.
/// Nothing moves in the books until the shop approves it.
class CustomerPayScreen extends StatefulWidget {
  const CustomerPayScreen({
    super.key,
    required this.repo,
    required this.businessId,
    required this.businessName,
    required this.outstanding,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceBalance,
  });

  final Repo repo;
  final int businessId;
  final String businessName;
  final double outstanding;
  final int? invoiceId;
  final String? invoiceNumber;
  final double? invoiceBalance;

  @override
  State<CustomerPayScreen> createState() => _CustomerPayScreenState();
}

class _CustomerPayScreenState extends State<CustomerPayScreen> with WidgetsBindingObserver {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  final _confirmKey = GlobalKey();

  ShopUpi? _upi;
  bool _loadingUpi = true;

  Uint8List? _imageBytes;
  String? _imageName;
  String? _imageType;
  bool _busy = false;
  String? _amountError;
  String? _error;

  /// True once the UPI app was opened; when the customer comes back we
  /// highlight the confirm step.
  bool _openedUpiApp = false;
  bool _cameBack = false;

  double get _maxPayable => widget.invoiceBalance ?? widget.outstanding;
  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  String get _payNote => widget.invoiceNumber != null
      ? 'Bill ${widget.invoiceNumber}'
      : 'Payment to ${widget.businessName}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _amount.text = _maxPayable.toStringAsFixed(2);
    _loadUpi();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedUpiApp && !_cameBack) {
      setState(() => _cameBack = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _confirmKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(ctx,
              duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> _loadUpi() async {
    try {
      final upi = await widget.repo.myShopUpi(widget.businessId);
      if (mounted) setState(() => _upi = upi);
    } catch (_) {
      // Without the shop's UPI the customer can still confirm a payment made
      // another way, so a failed load is not an error screen.
    } finally {
      if (mounted) setState(() => _loadingUpi = false);
    }
  }

  bool _checkAmount() {
    final amount = _amountValue;
    String? err;
    if (amount <= 0) {
      err = 'Enter the amount you want to pay.';
    } else if (amount > _maxPayable + 0.001) {
      err = 'You can pay at most ${money(_maxPayable)}.';
    }
    setState(() => _amountError = err);
    return err == null;
  }

  Future<void> _openUpiApp() async {
    if (!_checkAmount() || _upi == null) return;
    final link = _upi!.payLink(amount: _amountValue, note: _payNote);
    var ok = false;
    try {
      ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalNonBrowserApplication);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      setState(() {
        _openedUpiApp = true;
        _cameBack = false;
      });
    } else {
      showSnack(
        context,
        'No UPI app found. Install Google Pay, PhonePe, Paytm or BHIM, '
        'or pay to ${_upi!.upiId} and confirm below.',
        error: true,
      );
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1600,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          showSnack(context, 'That image is over 5 MB. Try a smaller one.', error: true);
        }
        return;
      }

      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name;
        _imageType = picked.mimeType ?? _guessType(picked.name);
      });
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the image: $e', error: true);
    }
  }

  static String _guessType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _submit() async {
    if (!_checkAmount()) return;
    final ref = _reference.text.trim();
    final refOk = RegExp(r'^\d{12}$').hasMatch(ref);

    if (ref.isNotEmpty && !refOk) {
      setState(() => _error = 'The UPI reference (UTR) is the 12-digit number '
          'on the payment success screen.');
      return;
    }
    if (!refOk && _imageBytes == null) {
      setState(() => _error = 'Enter the 12-digit UPI reference number, '
          'or attach the payment screenshot.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final msg = await widget.repo.submitPaymentProof(
        businessId: widget.businessId,
        amount: _amountValue,
        invoiceId: widget.invoiceId,
        referenceNo: ref,
        note: _note.text.trim(),
        imageBytes: _imageBytes,
        imageName: _imageName,
        imageContentType: _imageType,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.check_circle, color: moneyPositive(ctx), size: 44),
          title: const Text('Sent to the shop'),
          content: Text(
            '${widget.businessName} has been told you paid ${money(_amountValue)}.\n\n'
            'Your balance will update as soon as they confirm the money reached them.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      showSnack(context, msg);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ------------------------------------------------------------------ UI

  Widget _heading(String number, String text, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: color ?? scheme.primary,
            child: Text(number,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _payWithUpi() {
    final scheme = Theme.of(context).colorScheme;
    final upi = _upi!;
    final amount = _amountValue;

    if (!isMobileDevice) {
      // A PC has no UPI apps: show a big QR to scan with the phone.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Open Google Pay, PhonePe, Paytm or your bank app on your phone and scan this QR. '
            'The amount is already filled in.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          UpiQrCard(upi: upi, amount: amount > 0 ? amount : null, note: _payNote, size: 260),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              copyUpiId(context, upi.upiId!);
              setState(() => _cameBack = true);
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copy UPI ID'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F5C43),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
          ),
          onPressed: _openUpiApp,
          icon: const Icon(Icons.account_balance_wallet_outlined),
          label: Text(amount > 0 ? 'Pay ${money(amount)} with UPI app' : 'Pay with UPI app'),
        ),
        const SizedBox(height: 6),
        Text(
          'Opens Google Pay, PhonePe, Paytm, BHIM or your bank app with '
          '${upi.upiName} and the amount filled in. Money goes straight to the shop.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.35, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        UpiQrCard(upi: upi, amount: amount > 0 ? amount : null, note: _payNote),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => shareUpiQr(context, upi,
                    amount: amount > 0 ? amount : null, note: _payNote),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('Save / share QR'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => copyUpiId(context, upi.upiId!),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy UPI ID'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Paying from this phone and the button does not work? Save the QR, then in '
          'your UPI app choose "Scan QR" -> "Upload from gallery".',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, height: 1.35, color: scheme.outline),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasUpi = _upi?.isSetUp == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Pay the shop')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ------------------------------------------------ what is owed
          Card(
            color: scheme.primaryContainer.withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    child: const Icon(Icons.storefront),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.businessName,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        if (widget.invoiceNumber != null)
                          Text('Against bill ${widget.invoiceNumber}',
                              style: const TextStyle(fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          widget.invoiceBalance != null
                              ? 'Balance on this bill: ${money(widget.invoiceBalance)}'
                              : 'You owe: ${money(widget.outstanding)}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: moneyNegative(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ------------------------------------------------ amount
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _amountError = null),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              labelText: 'Amount to pay',
              helperText: 'Pay the full amount or any part of it',
              prefixText: '₹ ',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: Text('Full ${money(_maxPayable)}'),
                onPressed: () => setState(() {
                  _amount.text = _maxPayable.toStringAsFixed(2);
                  _amountError = null;
                }),
              ),
              if (_maxPayable >= 200)
                ActionChip(
                  label: Text('Half ${money((_maxPayable / 2).roundToDouble())}'),
                  onPressed: () => setState(() {
                    _amount.text = (_maxPayable / 2).roundToDouble().toStringAsFixed(2);
                    _amountError = null;
                  }),
                ),
            ],
          ),

          // ------------------------------------------------ step 1: pay
          const SizedBox(height: 22),
          _heading('1', 'Pay directly to the shop'),
          if (_loadingUpi)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CoinLoader()),
            )
          else if (hasUpi)
            _payWithUpi()
          else
            Card(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('This shop has not added its UPI ID yet'),
                subtitle: Text('Pay them the way you usually do (UPI to their number, '
                    'bank transfer...), then confirm the payment below.'),
              ),
            ),

          // ------------------------------------------------ step 2: confirm
          const SizedBox(height: 26),
          Container(
            key: _confirmKey,
            padding: _cameBack ? const EdgeInsets.all(14) : EdgeInsets.zero,
            decoration: _cameBack
                ? BoxDecoration(
                    color: moneyPositive(context).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: moneyPositive(context), width: 1.5),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading('2', 'Confirm your payment',
                    color: _cameBack ? moneyPositive(context) : null),
                if (_cameBack)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Welcome back! If the payment was successful, enter the 12-digit '
                      'UPI reference number from the success screen so the shop can match it.',
                      style: TextStyle(fontSize: 13, height: 1.35, color: scheme.onSurface),
                    ),
                  ),
                TextField(
                  controller: _reference,
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  decoration: const InputDecoration(
                    labelText: 'UPI reference number (UTR)',
                    hintText: '12 digits, e.g. 426512345678',
                    prefixIcon: Icon(Icons.tag),
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note for the shop (optional)',
                    prefixIcon: Icon(Icons.edit_note),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Payment screenshot (optional if you entered the UTR)',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                if (_imageBytes != null)
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                        ),
                        ListTile(
                          dense: true,
                          leading: Icon(Icons.check_circle, color: moneyPositive(context)),
                          title: Text(_imageName ?? 'screenshot',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${(_imageBytes!.length / 1024).round()} KB'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => setState(() {
                              _imageBytes = null;
                              _imageName = null;
                            }),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: const Text('Gallery'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pick(ImageSource.camera),
                          icon: const Icon(Icons.photo_camera_outlined, size: 18),
                          label: const Text('Camera'),
                        ),
                      ),
                    ],
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: _busy
                      ? CoinLoader(size: 20)
                      : const Icon(Icons.send),
                  label: Text(_busy
                      ? 'Sending...'
                      : 'I have paid ${_amountValue > 0 ? money(_amountValue) : ''} - tell the shop'),
                ),
                const SizedBox(height: 10),
                Text(
                  'The shop gets a message straight away and checks their bank. Your '
                  'balance updates once they approve it, and you get the updated bill.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.4, color: scheme.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The customer's list of sent payments and where each one stands.
class MyPaymentProofsSection extends StatelessWidget {
  const MyPaymentProofsSection({
    super.key,
    required this.proofs,
    required this.repo,
    required this.onChanged,
  });

  final List<PaymentProof> proofs;
  final Repo repo;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (proofs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payments you sent',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < proofs.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    switch (proofs[i].status) {
                      'Approved' => Icons.check_circle,
                      'Rejected' => Icons.cancel_outlined,
                      'Cancelled' => Icons.block,
                      _ => Icons.hourglass_top,
                    },
                    color: statusColor(proofs[i].status, Theme.of(context).colorScheme),
                  ),
                  title: Text(money(proofs[i].amount),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    '${proofs[i].businessName}  -  ${relative(proofs[i].submittedAt)}'
                    '${(proofs[i].remarks ?? '').isEmpty ? '' : '\n${proofs[i].remarks}'}',
                  ),
                  isThreeLine: (proofs[i].remarks ?? '').isNotEmpty,
                  trailing: proofs[i].isPending
                      ? TextButton(
                          onPressed: () async {
                            try {
                              final msg = await repo.cancelMyProof(proofs[i].id);
                              if (context.mounted) showSnack(context, msg);
                              await onChanged();
                            } on ApiException catch (e) {
                              if (context.mounted) {
                                showSnack(context, e.message, error: true);
                              }
                            }
                          },
                          child: const Text('Cancel'),
                        )
                      : StatusPill(proofs[i].status),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
