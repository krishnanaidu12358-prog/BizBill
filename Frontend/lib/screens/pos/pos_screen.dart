import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../models/models.dart';
import '../../models/proof_models.dart';
import '../../services/repo.dart';
import '../../widgets/barcode_scanner.dart';
import '../../widgets/common.dart';
import '../../widgets/invoice_actions.dart';
import 'pos_checkout.dart';

/// One line in the counter basket.
class _CartLine {
  _CartLine(this.product) : quantity = 1;

  final Product product;
  double quantity;

  double get price => product.sellingPrice;
  double get gross => price * quantity;
  double get tax => gross * product.taxPercent / 100;
  double get total => gross + tax;

  Map<String, dynamic> toJson() => {
        'productId': product.id,
        'quantity': quantity,
        'unitPrice': price,
        'taxPercent': product.taxPercent,
      };
}

/// Supermarket-style counter billing (POS). Built for a Windows counter PC with
/// a USB / Bluetooth barcode scanner - the scanner "types" the code and presses
/// Enter, so every beep adds the item and the total updates on its own.
/// Also works on a phone with the camera.
///
/// Keys: F2 scan box, F4 pay (split), F5 cash, F6 UPI QR, F7 card, F8 customer,
/// F9 clear sale. Type "3*" before a code to add 3 at once.
class PosScreen extends StatefulWidget {
  const PosScreen({
    super.key,
    required this.repo,
    this.isWorker = false,
    this.workerCanGiveUdhaar = false,
  });

  final Repo repo;
  final bool isWorker;
  final bool workerCanGiveUdhaar;

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  static const _kAutoPrint = 'pos_auto_print';

  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  final _discount = TextEditingController();

  final List<_CartLine> _lines = [];
  List<Product> _products = [];
  List<Customer>? _customers;
  Customer? _walkIn;
  Customer? _customer;
  ShopUpi? _upi;

  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _autoPrint = false;
  int? _lastIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scan.dispose();
    _scanFocus.dispose();
    _discount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        widget.repo.products(),
        widget.repo.walkInCustomer(),
      ]);
      _products = results[0] as List<Product>;
      _walkIn = results[1] as Customer;
      _customer ??= _walkIn;
    } on ApiException catch (e) {
      _loadError = e.message;
    }
    try {
      _upi = await widget.repo.shopUpi();
    } catch (_) {
      // UPI QR is optional at checkout.
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoPrint = prefs.getBool(_kAutoPrint) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    _focusScan();
  }

  void _focusScan() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocus.requestFocus();
    });
  }

  // ------------------------------------------------------------------ maths

  double get _subTotal => _lines.fold(0.0, (s, l) => s + l.gross);
  double get _tax => _lines.fold(0.0, (s, l) => s + l.tax);
  double get _qtyTotal => _lines.fold(0.0, (s, l) => s + l.quantity);
  double get _discountValue => (double.tryParse(_discount.text) ?? 0).clamp(0, _subTotal).toDouble();
  double get _total =>
      double.parse((_subTotal - _discountValue + _tax).clamp(0, double.infinity).toStringAsFixed(2));

  bool get _isWalkIn => _customer?.mobile == '0000000000';

  bool get _canLeaveUdhaar {
    final c = _customer;
    if (c == null || _isWalkIn || !c.isTrusted) return false;
    if (widget.isWorker && !widget.workerCanGiveUdhaar) return false;
    return true;
  }

  // ---------------------------------------------------------------- scanning

  Future<void> _onScan(String raw) async {
    var text = raw.trim();
    _scan.clear();
    if (text.isEmpty) return;

    // "3*8901234567890" adds three.
    var count = 1.0;
    final star = RegExp(r'^(\d+(?:\.\d+)?)\s*[*xX]\s*(.+)$').firstMatch(text);
    if (star != null) {
      count = double.tryParse(star.group(1)!) ?? 1;
      text = star.group(2)!.trim();
    }

    Product? p = _findByCode(text);
    if (p == null) {
      try {
        p = await widget.repo.productByBarcode(text);
        _products.add(p);
      } on ApiException {
        p = null;
      }
    }
    // Not a code: treat it as a name search.
    if (p == null && mounted) {
      final q = text.toLowerCase();
      final hits = _products.where((x) => x.name.toLowerCase().contains(q)).toList();
      if (hits.length == 1) {
        p = hits.first;
      } else if (hits.isNotEmpty) {
        p = await _pickProduct(initial: text);
      } else {
        SystemSound.play(SystemSoundType.alert);
        HapticFeedback.heavyImpact();
        showSnack(context, 'No product with code or name "$text". Add it under Stock first.', error: true);
      }
    }

    if (p != null) _addProduct(p, count);
    _focusScan();
  }

  Product? _findByCode(String code) {
    final lower = code.toLowerCase();
    for (final x in _products) {
      if (x.barcode == code || (x.sku != null && x.sku!.toLowerCase() == lower)) return x;
    }
    return null;
  }

  void _addProduct(Product p, [double count = 1]) {
    final i = _lines.indexWhere((l) => l.product.id == p.id);
    final already = i >= 0 ? _lines[i].quantity : 0.0;
    if (already + count > p.stockQty + 0.0001) {
      SystemSound.play(SystemSoundType.alert);
      showSnack(
          context,
          p.stockQty <= 0
              ? '${p.name} is out of stock.'
              : 'Not enough stock for ${p.name} - only ${qty(p.stockQty)} ${p.unit} in stock.',
          error: true);
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      if (i >= 0) {
        _lines[i].quantity += count;
        _lastIndex = i;
      } else {
        final line = _CartLine(p)..quantity = count;
        _lines.add(line);
        _lastIndex = _lines.length - 1;
      }
    });
  }

  Future<void> _scanWithCamera() async {
    final code = await scanBarcodeWithCamera(context);
    if (code != null) await _onScan(code);
  }

  Future<Product?> _pickProduct({String initial = ''}) {
    return showDialog<Product>(
      context: context,
      builder: (_) => _ProductPicker(products: _products, initial: initial),
    );
  }

  Future<void> _browseProducts() async {
    final p = await _pickProduct();
    if (p != null) _addProduct(p);
    _focusScan();
  }

  void _setQty(int i, double q) {
    final line = _lines[i];
    if (q <= 0) {
      setState(() {
        _lines.removeAt(i);
        _lastIndex = null;
      });
      return;
    }
    if (q > line.product.stockQty + 0.0001) {
      showSnack(context, 'Only ${line.product.stockQty} ${line.product.unit} in stock.', error: true);
      return;
    }
    setState(() => line.quantity = q);
  }

  Future<void> _editQty(int i) async {
    final c = TextEditingController(text: qty(_lines[i].quantity));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_lines[i].product.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Quantity (${_lines[i].product.unit})'),
          onSubmitted: (t) => Navigator.pop(ctx, double.tryParse(t.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim())),
              child: const Text('OK')),
        ],
      ),
    );
    if (v != null) _setQty(i, v);
    _focusScan();
  }

  Future<void> _clearSale({bool ask = true}) async {
    if (_lines.isEmpty) return;
    if (ask) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clear this sale?'),
          content: Text('${_lines.length} item(s) will be removed.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
          ],
        ),
      );
      if (ok != true) {
        _focusScan();
        return;
      }
    }
    setState(() {
      _lines.clear();
      _discount.clear();
      _lastIndex = null;
      _customer = _walkIn;
    });
    _focusScan();
  }

  // --------------------------------------------------------------- customer

  Future<void> _chooseCustomer() async {
    try {
      _customers ??= await widget.repo.customers();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<Object>(
      context: context,
      builder: (_) => _CustomerPicker(customers: _customers!, repo: widget.repo),
    );
    if (picked is Customer) {
      setState(() => _customer = picked);
    } else if (picked == 'walkin') {
      setState(() => _customer = _walkIn);
    } else if (picked == 'reload') {
      _customers = null;
    }
    _focusScan();
  }

  // ---------------------------------------------------------------- checkout

  Future<void> _pay(String mode) async {
    if (_saving) return;
    if (_lines.isEmpty) {
      showSnack(context, 'Scan an item first.', error: true);
      _focusScan();
      return;
    }
    if (_customer == null) {
      showSnack(context, 'Could not load the walk-in customer. Pick a customer.', error: true);
      return;
    }

    final result = await showPosCheckout(
      context,
      total: _total,
      initialMode: mode,
      upi: _upi,
      billLabel: 'Bill for ${_isWalkIn ? 'counter sale' : _customer!.name}',
      allowUdhaar: _canLeaveUdhaar,
      customerName: _isWalkIn ? null : _customer!.name,
    );
    if (result == null || !mounted) {
      _focusScan();
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await widget.repo.createInvoice({
        'customerId': _customer!.id,
        'items': _lines.map((l) => l.toJson()).toList(),
        'discountAmount': _discountValue,
        'paymentMode': result.tenders.isEmpty ? 'Credit' : result.tenders.first.mode,
        'paidAmount': result.paid,
        'tenders': result.tenders.map((t) => t.toJson()).toList(),
        if (result.cashTendered != null) 'cashTendered': result.cashTendered,
        'sendWhatsApp': !_isWalkIn,
      });
      if (!mounted) return;
      final inv = Invoice.fromJson(res.data as Map<String, dynamic>);
      HapticFeedback.mediumImpact();

      // Stock on hand changed; refresh the local copy quietly for the next sale.
      for (final l in _lines) {
        final i = _products.indexWhere((p) => p.id == l.product.id);
        if (i >= 0) {
          final p = _products[i];
          _products[i] = Product(
            id: p.id,
            name: p.name,
            unit: p.unit,
            sellingPrice: p.sellingPrice,
            taxPercent: p.taxPercent,
            stockQty: p.stockQty - l.quantity,
            minStockQty: p.minStockQty,
            isLowStock: p.stockQty - l.quantity <= p.minStockQty,
            sku: p.sku,
            barcode: p.barcode,
          );
        }
      }

      setState(() {
        _lines.clear();
        _discount.clear();
        _lastIndex = null;
        _customer = _walkIn;
      });

      if (_autoPrint) InvoiceActions.printReceipt(context, inv);
      await showDialog<void>(
        context: context,
        builder: (_) => _SaleDone(
          invoice: inv,
          change: result.change,
          repo: widget.repo,
          autoPrinted: _autoPrint,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
      _focusScan();
    }
  }

  Future<void> _toggleAutoPrint(bool v) async {
    setState(() => _autoPrint = v);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAutoPrint, v);
    } catch (_) {}
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): _focusScan,
        const SingleActivator(LogicalKeyboardKey.f4): () => _pay('Cash'),
        const SingleActivator(LogicalKeyboardKey.f5): () => _pay('Cash'),
        const SingleActivator(LogicalKeyboardKey.f6): () => _pay('UPI'),
        const SingleActivator(LogicalKeyboardKey.f7): () => _pay('Card'),
        const SingleActivator(LogicalKeyboardKey.f8): _chooseCustomer,
        const SingleActivator(LogicalKeyboardKey.f9): _clearSale,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Counter billing'),
            actions: [
              IconButton(
                tooltip: 'Choose receipt printer',
                icon: const Icon(Icons.print_outlined),
                onPressed: () => InvoiceActions.chooseReceiptPrinter(context),
              ),
              Row(
                children: [
                  const Text('Auto-print', style: TextStyle(fontSize: 13)),
                  Switch(value: _autoPrint, onChanged: _toggleAutoPrint),
                ],
              ),
              IconButton(
                tooltip: 'Reload products',
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CoinLoader())
              : _loadError != null
                  ? ErrorView(message: _loadError!, onRetry: _load)
                  : wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _basketPanel(context, wide: true)),
                            SizedBox(width: 390, child: _summaryPanel(context, wide: true)),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(child: _basketPanel(context, wide: false)),
                            _summaryPanel(context, wide: false),
                          ],
                        ),
        ),
      ),
    );
  }

  Widget _scanBox(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _scan,
            focusNode: _scanFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: _onScan,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.qr_code_scanner),
              hintText: isMobileDevice
                  ? 'Scan with camera, or type code / name'
                  : 'Scan barcode / QR, or type code or name + Enter  (F2)',
              suffixIcon: IconButton(
                tooltip: 'Find product',
                icon: const Icon(Icons.search),
                onPressed: _browseProducts,
              ),
            ),
          ),
        ),
        if (isMobileDevice) ...[
          const SizedBox(width: 8),
          IconButton.filled(
            iconSize: 28,
            tooltip: 'Scan with camera',
            onPressed: _scanWithCamera,
            icon: const Icon(Icons.photo_camera_outlined),
          ),
        ],
      ],
    );
  }

  Widget _basketPanel(BuildContext context, {required bool wide}) {
    final scheme = Theme.of(context).colorScheme;
    final last = _lastIndex != null && _lastIndex! < _lines.length ? _lines[_lastIndex!] : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, wide ? 6 : 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _scanBox(context),
          const SizedBox(height: 10),
          // Big "last scanned" strip, like a supermarket pole display.
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: last == null
                  ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                  : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(last == null ? Icons.shopping_basket_outlined : Icons.check_circle,
                    color: last == null ? scheme.outline : scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    last == null ? 'Scan a product to start' : last.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                if (last != null)
                  Text('${qty(last.quantity)} x ${money(last.price)}',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: scheme.primary)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (wide && _lines.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: DefaultTextStyle(
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
                child: const Row(
                  children: [
                    SizedBox(width: 32, child: Text('#')),
                    Expanded(child: Text('ITEM')),
                    SizedBox(width: 90, child: Text('PRICE', textAlign: TextAlign.right)),
                    SizedBox(width: 150, child: Text('QTY', textAlign: TextAlign.center)),
                    SizedBox(width: 110, child: Text('AMOUNT', textAlign: TextAlign.right)),
                    SizedBox(width: 44),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _lines.isEmpty
                ? const EmptyState(
                    icon: Icons.qr_code_scanner,
                    title: 'Basket is empty',
                    subtitle: 'Scan the barcode or QR on each pack. The price shows and the total '
                        'adds up by itself.',
                  )
                : ListView.separated(
                    itemCount: _lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _lineRow(context, i, wide),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(BuildContext context, int i, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final l = _lines[i];
    final highlight = i == _lastIndex;

    final qtyControl = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: () => _setQty(i, l.quantity - 1),
        ),
        InkWell(
          onTap: () => _editQty(i),
          child: Container(
            constraints: const BoxConstraints(minWidth: 42),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(qty(l.quantity),
                textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => _setQty(i, l.quantity + 1),
        ),
      ],
    );

    final remove = IconButton(
      tooltip: 'Remove',
      icon: Icon(Icons.delete_outline, color: scheme.error),
      onPressed: () => _setQty(i, 0),
    );

    final sub = [
      if ((l.product.barcode ?? '').isNotEmpty) l.product.barcode!,
      if (l.product.taxPercent > 0) 'GST ${qty(l.product.taxPercent)}%',
    ].join('  ·  ');

    return Container(
      color: highlight ? scheme.primaryContainer.withValues(alpha: 0.25) : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: wide
          ? Row(
              children: [
                SizedBox(width: 32, child: Text('${i + 1}')),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (sub.isNotEmpty)
                        Text(sub, style: TextStyle(fontSize: 11.5, color: scheme.outline)),
                    ],
                  ),
                ),
                SizedBox(width: 90, child: Text(money(l.price), textAlign: TextAlign.right)),
                SizedBox(width: 150, child: Center(child: qtyControl)),
                SizedBox(
                  width: 110,
                  child: Text(money(l.total),
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                SizedBox(width: 44, child: remove),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text('${money(l.price)} / ${l.product.unit}'
                          '${l.product.taxPercent > 0 ? '  +GST ${qty(l.product.taxPercent)}%' : ''}',
                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                    ],
                  ),
                ),
                qtyControl,
                SizedBox(
                  width: 82,
                  child: Text(money(l.total),
                      textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
    );
  }

  Widget _summaryPanel(BuildContext context, {required bool wide}) {
    final scheme = Theme.of(context).colorScheme;
    final c = _customer;

    final payButtons = [
      _PayButton(
        label: 'Cash',
        hint: 'F5',
        icon: Icons.payments_outlined,
        color: const Color(0xFF1B7F3B),
        onTap: _saving ? null : () => _pay('Cash'),
      ),
      _PayButton(
        label: 'UPI QR',
        hint: 'F6',
        icon: Icons.qr_code_2,
        color: const Color(0xFF0F5C43),
        onTap: _saving ? null : () => _pay('UPI'),
      ),
      _PayButton(
        label: 'Card',
        hint: 'F7',
        icon: Icons.credit_card,
        color: const Color(0xFF3949AB),
        onTap: _saving ? null : () => _pay('Card'),
      ),
    ];

    final customerTile = Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        leading: Icon(_isWalkIn ? Icons.storefront_outlined : Icons.person_outline),
        title: Text(c == null ? 'No customer' : (_isWalkIn ? 'Walk-in customer' : c.name),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(_isWalkIn
            ? 'Counter sale - tap to add customer (F8)'
            : '+91 ${c!.mobile}${c.outstandingBalance > 0 ? '  ·  owes ${money(c.outstandingBalance)}' : ''}'),
        trailing: const Icon(Icons.swap_horiz),
        onTap: _chooseCustomer,
      ),
    );

    if (!wide) {
      return Material(
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                customerTile,
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('${_lines.length} items · ${qty(_qtyTotal)} qty',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                    const Spacer(),
                    Text(money(_total),
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: scheme.primary)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(children: [
                  for (final b in payButtons) Expanded(child: Padding(padding: const EdgeInsets.all(3), child: b)),
                ]),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(6, 12, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          customerTile,
          const SizedBox(height: 12),
          MoneyRow('Items ${_lines.length}  ·  Qty ${qty(_qtyTotal)}', _subTotal),
          Row(
            children: [
              const Expanded(child: Text('Discount')),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _discount,
                  textAlign: TextAlign.right,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _focusScan(),
                  decoration: const InputDecoration(isDense: true, prefixText: '₹ ', hintText: '0'),
                ),
              ),
            ],
          ),
          if (_tax > 0) MoneyRow('GST', _tax),
          const Divider(height: 22),
          Text('TOTAL', style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(_total),
                style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: scheme.primary)),
          ),
          const SizedBox(height: 12),
          for (final b in payButtons) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _pay('Cash'),
            icon: const Icon(Icons.call_split),
            label: const Text('Split payment  (F4)'),
          ),
          const Spacer(),
          if (_saving) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _lines.isEmpty ? null : _clearSale,
            icon: const Icon(Icons.clear_all),
            label: const Text('Clear sale  (F9)'),
          ),
          Text('F2 scan · F4 split · F5 cash · F6 UPI · F7 card · F8 customer\nType 3*code to add 3 at once',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: scheme.outline)),
        ],
      ),
    );
  }
}

class _PayButton extends StatelessWidget {
  const _PayButton({
    required this.label,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String hint;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      onPressed: onTap,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          if (!isMobileDevice) ...[
            const SizedBox(width: 6),
            Text(hint, style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ pickers

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.products, this.initial = ''});
  final List<Product> products;
  final String initial;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  late final _q = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _q.text.trim().toLowerCase();
    final list = widget.products
        .where((p) =>
            q.isEmpty ||
            p.name.toLowerCase().contains(q) ||
            (p.sku ?? '').toLowerCase().contains(q) ||
            (p.barcode ?? '').contains(q))
        .toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 620),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (list.isNotEmpty) Navigator.pop(context, list.first);
                },
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Product name, SKU or barcode'),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('No matching product'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final p = list[i];
                        return ListTile(
                          enabled: p.stockQty > 0,
                          title: Text(p.name),
                          subtitle: Text('Stock ${qty(p.stockQty)} ${p.unit}'
                              '${(p.barcode ?? '').isNotEmpty ? '  ·  ${p.barcode}' : ''}'),
                          trailing: Text(money(p.sellingPrice),
                              style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
                          onTap: () => Navigator.pop(context, p),
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

/// Returns a [Customer], 'walkin', or 'reload' (after adding a new one).
class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.customers, required this.repo});
  final List<Customer> customers;
  final Repo repo;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  final _q = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _addNew() async {
    final name = TextEditingController();
    final mobile = TextEditingController(
        text: RegExp(r'^\d{10}$').hasMatch(_q.text.trim()) ? _q.text.trim() : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mobile,
              autofocus: true,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Mobile', prefixText: '+91 '),
            ),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.createCustomer({'mobile': mobile.text.trim(), 'name': name.text.trim()});
      final fresh = await widget.repo.customers(search: mobile.text.trim());
      if (!mounted) return;
      final match = fresh.where((c) => c.mobile == mobile.text.trim()).toList();
      Navigator.pop(context, match.isNotEmpty ? match.first : 'reload');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final list = widget.customers
        .where((c) =>
            c.mobile != '0000000000' &&
            (q.isEmpty || c.name.toLowerCase().contains(q) || c.mobile.contains(q)))
        .toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (list.length == 1) Navigator.pop(context, list.first);
                },
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Customer name or mobile'),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Walk-in customer'),
              subtitle: const Text('No name or number'),
              onTap: () => Navigator.pop(context, 'walkin'),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: const Text('Add new customer'),
              trailing: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : null,
              onTap: _busy ? null : _addNew,
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    title: Text(c.name),
                    subtitle: Text('+91 ${c.mobile}'
                        '${c.outstandingBalance > 0 ? '  ·  owes ${money(c.outstandingBalance)}' : ''}'),
                    trailing: c.isTrusted ? const Icon(Icons.verified_outlined, size: 18) : null,
                    onTap: () => Navigator.pop(context, c),
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

// ----------------------------------------------------------------- sale done

class _SaleDone extends StatelessWidget {
  const _SaleDone({
    required this.invoice,
    required this.change,
    required this.repo,
    required this.autoPrinted,
  });

  final Invoice invoice;
  final double change;
  final Repo repo;
  final bool autoPrinted;

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF1B7F3B);
    final scheme = Theme.of(context).colorScheme;
    final walkIn = invoice.customerMobile == '0000000000';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP): () => InvoiceActions.printReceipt(context, invoice),
      },
      child: AlertDialog(
        icon: const Icon(Icons.check_circle, color: green, size: 48),
        title: Text('Bill ${invoice.invoiceNumber} saved'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MoneyRow('Total', invoice.grandTotal, bold: true),
              for (final t in invoice.tenders) MoneyRow(t.label, t.amount),
              if (invoice.balanceAmount > 0)
                MoneyRow('Udhaar (balance)', invoice.balanceAmount, tone: scheme.error),
              if (change > 0.009) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text('Give back change', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text(money(change),
                          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: green)),
                    ],
                  ),
                ),
              ],
              if (autoPrinted)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Receipt sent to the printer.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.outline, fontSize: 12)),
                ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => InvoiceActions.printReceipt(context, invoice),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Print receipt (P)'),
          ),
          OutlinedButton.icon(
            onPressed: () => InvoiceActions.sharePdf(context, invoice),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('PDF'),
          ),
          if (!walkIn)
            OutlinedButton.icon(
              onPressed: () => InvoiceActions.sendWhatsApp(context, repo, invoice),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Next customer (Enter)'),
          ),
        ],
      ),
    );
  }
}
