import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../models/proof_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import '../../widgets/upi_qr.dart';

/// The shop owner adds their UPI ID once. From then on every customer sees the
/// shop's QR and a "Pay with UPI app" button, and the money lands directly in
/// the owner's bank account.
class OwnerUpiScreen extends StatefulWidget {
  const OwnerUpiScreen({super.key, required this.repo});

  final Repo repo;

  @override
  State<OwnerUpiScreen> createState() => _OwnerUpiScreenState();
}

class _OwnerUpiScreenState extends State<OwnerUpiScreen> {
  final _upiId = TextEditingController();
  final _upiName = TextEditingController();

  ShopUpi? _saved;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

  static final _pattern = RegExp(r'^[a-zA-Z0-9.\-_]{2,256}@[a-zA-Z][a-zA-Z0-9]{1,63}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _upiId.dispose();
    _upiName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final upi = await widget.repo.shopUpi();
      _saved = upi;
      _upiId.text = upi.upiId ?? '';
      _upiName.text = upi.upiName;
    } on ApiException catch (e) {
      _loadError = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  ShopUpi get _preview => ShopUpi(
        businessId: _saved?.businessId ?? 0,
        businessName: _saved?.businessName ?? '',
        upiId: _upiId.text.trim(),
        upiName: _upiName.text.trim().isEmpty
            ? (_saved?.businessName ?? '')
            : _upiName.text.trim(),
      );

  bool get _validId => _pattern.hasMatch(_upiId.text.trim());

  Future<void> _save({bool turnOff = false}) async {
    final id = turnOff ? '' : _upiId.text.trim();
    if (!turnOff && !_validId) {
      setState(() => _error = 'Enter a UPI ID like shopname@okaxis or 9876543210@ybl.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await widget.repo.saveShopUpi(id, _upiName.text.trim());
      final upi = ShopUpi.fromJson(res.data as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _saved = upi;
        _upiId.text = upi.upiId ?? '';
      });
      showSnack(context, res.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('UPI payment QR')),
        body: const Center(child: CoinLoader()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('UPI payment QR')),
        body: ErrorView(message: _loadError!, onRetry: _load),
      );
    }

    final isLive = _saved?.isSetUp == true;
    final unsaved = _upiId.text.trim() != (_saved?.upiId ?? '');

    return Scaffold(
      appBar: AppBar(title: const Text('UPI payment QR')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Card(
            color: isLive
                ? const Color(0xFF1B7F3B).withValues(alpha: 0.1)
                : scheme.tertiaryContainer.withValues(alpha: 0.5),
            child: ListTile(
              leading: Icon(isLive ? Icons.verified : Icons.qr_code_2,
                  color: isLive ? const Color(0xFF1B7F3B) : scheme.tertiary, size: 30),
              title: Text(isLive ? 'Customers can pay you by UPI' : 'Get paid directly by UPI',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(isLive
                  ? 'Your QR shows on every customer\'s Pay screen. When they pay, '
                      'you get a message and approve it under Customer payments.'
                  : 'Add your UPI ID. Customers will see your QR and can pay you straight '
                      'from Google Pay, PhonePe or Paytm inside BizBill.'),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _upiId,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              labelText: 'Your UPI ID',
              hintText: 'e.g. lakshmistores@okaxis',
              helperText: 'Find it in your UPI app under Profile / "UPI ID". '
                  'Money goes to the bank account linked to it.',
              helperMaxLines: 2,
              prefixIcon: const Icon(Icons.alternate_email),
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _upiName,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Name customers see',
              hintText: 'Your shop name',
              prefixIcon: Icon(Icons.storefront_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(),
            icon: _saving
                ? CoinLoader(size: 20)
                : const Icon(Icons.save_outlined),
            label: Text(isLive ? 'Save changes' : 'Save & turn on UPI payments'),
          ),

          if (_validId) ...[
            const SizedBox(height: 22),
            Text(unsaved ? 'Preview (not saved yet)' : 'Your payment QR',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Print it for your counter too - any UPI app can scan it.',
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            UpiQrCard(upi: _preview),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => shareUpiQr(context, _preview),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share / save QR image'),
            ),
          ],

          if (isLive) ...[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: _saving ? null : () => _save(turnOff: true),
              icon: Icon(Icons.block, color: scheme.error),
              label: Text('Turn off UPI payments', style: TextStyle(color: scheme.error)),
            ),
          ],
        ],
      ),
    );
  }
}
