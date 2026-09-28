import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../models/proof_models.dart';
import '../../services/repo.dart';
import '../../widgets/barcode_scanner.dart';
import '../../widgets/collect_payment.dart';
import '../../widgets/common.dart';
import 'owner_bill_detail.dart';

/// One line on the bill: a stocked product, or a quick item typed in at the counter.
class _Line {
  _Line.product(Product p)
    : productId = p.id,
      name = p.name,
      unit = p.unit,
      price = p.sellingPrice,
      taxPercent = p.taxPercent,
      stock = p.stockQty,
      quantity = 1;

  _Line.quick({
    required this.name,
    required this.price,
    required this.quantity,
    this.taxPercent = 0,
  }) : productId = null,
       unit = 'PCS',
       stock = null;

  final int? productId;
  final String name;
  final String unit;
  final double price;
  final double taxPercent;

  /// Null for quick items, which have no stock to run out of.
  final double? stock;
  double quantity;

  double get gross => price * quantity;
  double get tax => gross * taxPercent / 100;
  double get total => gross + tax;

  Map<String, dynamic> toJson() => {
    if (productId != null) 'productId': productId else 'productName': name,
    'quantity': quantity,
    'unitPrice': price,
    'taxPercent': taxPercent,
  };
}

class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key, required this.repo, this.presetCustomer});

  final Repo repo;
  final Customer? presetCustomer;

  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  Customer? _customer;
  final List<_Line> _lines = [];
  final _discount = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String _mode = 'Cash';
  bool _sendWhatsApp = true;
  bool _busy = false;
  bool _paidTouched = false;

  List<Customer>? _customers;
  List<Product>? _products;
  String? _loadError;

  /// The shop's UPI, for the "collect by UPI" QR at checkout.
  ShopUpi? _upi;

  /// Barcode box. A USB / Bluetooth scanner types the code and presses Enter,
  /// so on Windows the cursor waits here and each beep adds the item.
  final _scan = TextEditingController();
  final _scanFocus = FocusNode();
  bool _walkInBusy = false;

  bool get _isWalkIn => _customer?.mobile == '0000000000';

  @override
  void initState() {
    super.initState();
    _customer = widget.presetCustomer;
    _loadMasters();
  }

  @override
  void dispose() {
    _discount.dispose();
    _paid.dispose();
    _notes.dispose();
    _scan.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _loadMasters() async {
    setState(() => _loadError = null);
    try {
      final results = await Future.wait([
        widget.repo.customers(),
        widget.repo.products(),
      ]);
      if (!mounted) return;
      setState(() {
        _customers = results[0] as List<Customer>;
        _products = results[1] as List<Product>;
      });
      // Ready to scan straight away on a counter PC.
      if (!isMobileDevice) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scanFocus.requestFocus());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    }
    try {
      final upi = await widget.repo.shopUpi();
      if (mounted) setState(() => _upi = upi);
    } catch (_) {
      // Checkout still works without it; the UPI step just shows no QR.
    }
  }

  /// Adds the scanned product (or one more of it). Looks in the loaded list
  /// first, then asks the server in case it was added after this screen opened.
  Future<void> _onScan(String raw) async {
    final code = raw.trim();
    _scan.clear();
    if (code.isEmpty) return;

    Product? p;
    for (final x in _products ?? const <Product>[]) {
      if (x.barcode == code || (x.sku != null && x.sku!.toLowerCase() == code.toLowerCase())) {
        p = x;
        break;
      }
    }
    if (p == null) {
      try {
        p = await widget.repo.productByBarcode(code);
        _products?.add(p);
      } on ApiException catch (e) {
        if (mounted) {
          HapticFeedback.heavyImpact();
          SystemSound.play(SystemSoundType.alert);
          showSnack(context, e.message, error: true);
        }
      }
    }

    if (p != null && mounted) {
      final product = p;
      HapticFeedback.selectionClick();
      setState(() {
        final existing = _lines.indexWhere((l) => l.productId == product.id);
        if (existing >= 0) {
          _setQty(existing, _lines[existing].quantity + 1);
        } else if (product.stockQty <= 0) {
          showSnack(context, '${product.name} is out of stock.', error: true);
        } else {
          _lines.add(_Line.product(product));
          _syncPaid();
        }
      });
    }
    if (mounted && !isMobileDevice) _scanFocus.requestFocus();
  }

  Future<void> _scanWithCamera() async {
    final code = await scanBarcodeWithCamera(context);
    if (code != null) await _onScan(code);
  }

  /// Counter sale with no name or number (supermarket / bar style).
  Future<void> _useWalkIn() async {
    setState(() => _walkInBusy = true);
    try {
      final c = await widget.repo.walkInCustomer();
      if (!mounted) return;
      setState(() {
        _customer = c;
        _sendWhatsApp = false;
        if (_mode == 'Credit') _mode = 'Cash';
        _paidTouched = false;
        _syncPaid();
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _walkInBusy = false);
    }
  }

  double get _subTotal => _lines.fold(0.0, (s, l) => s + l.gross);
  double get _tax => _lines.fold(0.0, (s, l) => s + l.tax);
  double get _discountValue {
    final d = double.tryParse(_discount.text) ?? 0;
    return d.clamp(0, _subTotal);
  }

  double get _grandTotal => double.parse(
    (_subTotal - _discountValue + _tax)
        .clamp(0, double.infinity)
        .toStringAsFixed(2),
  );
  double get _paidValue =>
      (double.tryParse(_paid.text) ?? 0).clamp(0, _grandTotal);
  double get _balance => _grandTotal - _paidValue;

  /// Until the cashier edits the field, "paid" tracks the total (the common case).
  void _syncPaid() {
    if (!_paidTouched) _paid.text = _grandTotal.toStringAsFixed(2);
  }

  /// A problem the API would reject, shown before the cashier taps Save.
  String? get _udhaarProblem {
    final c = _customer;
    if (c == null || _balance <= 0.009) return null;
    if (!c.isTrusted) {
      return '${c.name} is not a trusted customer, so this bill must be fully paid. '
          'Mark them trusted on the customer screen to allow Udhaar.';
    }
    final projected = c.outstandingBalance + _balance;
    if (c.creditLimit > 0 && projected > c.creditLimit) {
      return 'Credit limit ${money(c.creditLimit)} would be crossed '
          '(outstanding would be ${money(projected)}).';
    }
    return null;
  }

  Future<void> _pickCustomer() async {
    final list = _customers;
    if (list == null) return;

    final picked = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _PickerSheet<Customer>(
        title: 'Choose customer',
        items: list,
        searchOf: (c) => '${c.name} ${c.mobile}',
        tileBuilder: (c) => ListTile(
          leading: InitialsAvatar(c.name),
          title: Text(
            c.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '+91 ${c.mobile}'
            '${c.outstandingBalance > 0 ? '  ·  owes ${money(c.outstandingBalance)}' : ''}',
          ),
          trailing: c.isTrusted
              ? Icon(Icons.verified, size: 18, color: moneyPositive(ctx))
              : null,
          onTap: () => Navigator.pop(ctx, c),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _customer = picked;
        _syncPaid();
      });
    }
  }

  Future<void> _addProduct() async {
    final list = _products;
    if (list == null) return;

    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => _PickerSheet<Product>(
        title: 'Add item',
        items: list.where((p) => p.stockQty > 0).toList(),
        searchOf: (p) => '${p.name} ${p.sku ?? ''}',
        header: ListTile(
          leading: CircleAvatar(
            backgroundColor: Theme.of(ctx).colorScheme.secondaryContainer,
            child: const Icon(Icons.edit_note),
          ),
          title: const Text(
            'Quick item',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Not in stock list - type a name and price'),
          onTap: () => Navigator.pop(ctx, 'quick'),
        ),
        tileBuilder: (p) => ListTile(
          title: Text(
            p.name,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            'Stock ${qty(p.stockQty)} ${p.unit}'
            '${p.taxPercent > 0 ? '  ·  GST ${qty(p.taxPercent)}%' : ''}',
          ),
          trailing: Text(
            money(p.sellingPrice),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          onTap: () => Navigator.pop(ctx, p),
        ),
      ),
    );

    if (!mounted || picked == null) return;
    if (picked == 'quick') {
      final line = await _quickItemDialog();
      if (line != null) {
        setState(() {
          _lines.add(line);
          _syncPaid();
        });
      }
      return;
    }

    final p = picked as Product;
    setState(() {
      final existing = _lines.indexWhere((l) => l.productId == p.id);
      if (existing >= 0) {
        _setQty(existing, _lines[existing].quantity + 1);
      } else {
        _lines.add(_Line.product(p));
      }
      _syncPaid();
    });
  }

  Future<_Line?> _quickItemDialog() {
    final name = TextEditingController();
    final price = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final gst = TextEditingController(text: '0');
    final formKey = GlobalKey<FormState>();

    return showDialog<_Line>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quick item'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          prefixText: '₹ ',
                        ),
                        validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0
                            ? 'Enter price'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      child: TextFormField(
                        controller: quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Qty'),
                        validator: (v) =>
                            (double.tryParse(v ?? '') ?? 0) <= 0 ? '> 0' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: gst,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'GST %',
                    suffixText: '%',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 40)),
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                ctx,
                _Line.quick(
                  name: name.text.trim(),
                  price: double.parse(price.text),
                  quantity: double.parse(quantity.text),
                  taxPercent: (double.tryParse(gst.text) ?? 0)
                      .clamp(0, 28)
                      .toDouble(),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _setQty(int i, double q) {
    final line = _lines[i];
    if (q <= 0) {
      _lines.removeAt(i);
    } else if (line.stock != null && q > line.stock!) {
      showSnack(
        context,
        'Only ${qty(line.stock)} ${line.unit} of ${line.name} in stock.',
        error: true,
      );
    } else {
      line.quantity = q;
    }
    _syncPaid();
  }

  Future<void> _editQty(int i) async {
    final line = _lines[i];
    final ctrl = TextEditingController(text: qty(line.quantity));
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(line.name),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Quantity',
            suffixText: line.unit,
            helperText: line.stock == null
                ? null
                : 'In stock: ${qty(line.stock)}',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, double.tryParse(v)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            onPressed: () => Navigator.pop(ctx, double.tryParse(ctrl.text)),
            child: const Text('Set'),
          ),
        ],
      ),
    );
    if (value != null) setState(() => _setQty(i, value));
  }

  Future<bool?> _confirmBill() => showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => _ConfirmBillSheet(
      customer: _customer!,
      lines: _lines,
      subTotal: _subTotal,
      tax: _tax,
      discount: _discountValue,
      total: _grandTotal,
      paid: _paidValue,
      balance: _balance,
      mode: _paidValue <= 0 ? 'Credit' : _mode,
      notes: _notes.text.trim(),
      sendWhatsApp: _sendWhatsApp,
    ),
  );

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_customer == null) {
      showSnack(context, 'Choose a customer first.', error: true);
      return;
    }
    if (_lines.isEmpty) {
      showSnack(context, 'Add at least one item.', error: true);
      return;
    }
    final problem = _udhaarProblem;
    if (problem != null) {
      showSnack(context, problem, error: true);
      return;
    }

    // Review before anything is written: the owner sees the full bill and can
    // go back to edit it. Nothing reaches the API until they confirm.
    final confirmed = await _confirmBill();
    if (confirmed != true || !mounted) return;

    // Take the money the way a till does: QR on screen, card machine, or cash
    // with change. Cancelling here leaves the bill unsaved.
    var notes = _notes.text.trim();
    if (_paidValue > 0) {
      final collected = await collectPayment(
        context,
        mode: _mode == 'Credit' ? 'Cash' : _mode,
        amount: _paidValue,
        upi: _upi,
        billLabel: 'Bill for ${_customer!.name}',
      );
      if (collected == null || !mounted) return;
      if ((collected.note ?? '').isNotEmpty) {
        notes = notes.isEmpty ? collected.note! : '$notes | ${collected.note}';
      }
    }

    setState(() => _busy = true);
    try {
      final res = await widget.repo.createInvoice({
        'customerId': _customer!.id,
        'items': _lines.map((l) => l.toJson()).toList(),
        'discountAmount': _discountValue,
        'paymentMode': _paidValue <= 0 ? 'Credit' : _mode,
        'paidAmount': _paidValue,
        'notes': notes.isEmpty ? null : notes,
        'sendWhatsApp': _sendWhatsApp && !_isWalkIn,
      });

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final invoice = Invoice.fromJson(res.data as Map<String, dynamic>);
      showSnack(context, res.message);

      if (_sendWhatsApp && invoice.whatsAppLink != null) {
        await openWhatsApp(context, invoice.whatsAppLink);
      }
      if (!mounted) return;

      // Straight to the finished invoice, where it can be shared as PDF or printed.
      // `result: true` still tells the shell a bill was created.
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BillDetailScreen(
            repo: widget.repo,
            invoiceId: invoice.id,
            justCreated: true,
          ),
        ),
        result: true,
      );
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New bill')),
        body: ErrorView(message: _loadError!, onRetry: _loadMasters),
      );
    }
    if (_customers == null || _products == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New bill')),
        body: const Center(child: CoinLoader()),
      );
    }

    final problem = _udhaarProblem;

    // Counter keyboard shortcuts (Windows): F2 = scan box, F4 = add item,
    // F12 or Ctrl+Enter = save bill.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _scanFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f4): _addProduct,
        const SingleActivator(LogicalKeyboardKey.f12): () {
          if (!_busy) _save();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (!_busy) _save();
        },
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('New bill'),
        actions: [
          if (!isMobileDevice)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: Text('F2 scan  ·  F4 add item  ·  F12 save',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _TotalBar(
        total: _grandTotal,
        items: _lines.length,
        busy: _busy,
        onSave: _save,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            ResponsiveCenter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ------------------------------------------ customer
                  _CustomerCard(customer: _customer, onTap: _pickCustomer),
                  if (!_isWalkIn)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _walkInBusy ? null : _useWalkIn,
                        icon: _walkInBusy
                            ? CoinLoader(size: 16)
                            : const Icon(Icons.directions_walk, size: 20),
                        label: const Text('Walk-in customer (no name / number)'),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // ------------------------------------------ scan
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _scan,
                          focusNode: _scanFocus,
                          textInputAction: TextInputAction.done,
                          onSubmitted: _onScan,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.qr_code_scanner),
                            labelText: 'Scan barcode',
                            hintText: isMobileDevice
                                ? 'Type a code or tap the camera'
                                : 'Scan with the barcode scanner or type a code + Enter',
                          ),
                        ),
                      ),
                      if (isMobileDevice) ...[
                        const SizedBox(width: 10),
                        IconButton.filled(
                          tooltip: 'Scan with camera',
                          style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
                          onPressed: _scanWithCamera,
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ------------------------------------------ items
                  SectionHeader(
                    'Items',
                    subtitle: _lines.isEmpty
                        ? null
                        : 'Tap a quantity to type it · swipe to remove',
                    trailing: FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add item'),
                    ),
                  ),
                  if (_lines.isEmpty)
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _addProduct,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Column(
                            children: [
                              Icon(
                                Icons.add_shopping_cart,
                                size: 36,
                                color: scheme.outline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to add products',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Card(
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < _lines.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            Dismissible(
                              key: ObjectKey(_lines[i]),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                color: scheme.errorContainer,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: scheme.onErrorContainer,
                                ),
                              ),
                              onDismissed: (_) => setState(() {
                                _lines.removeAt(i);
                                _syncPaid();
                              }),
                              child: _LineTile(
                                line: _lines[i],
                                onMinus: () => setState(
                                  () => _setQty(i, _lines[i].quantity - 1),
                                ),
                                onPlus: () => setState(
                                  () => _setQty(i, _lines[i].quantity + 1),
                                ),
                                onEditQty: () => _editQty(i),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // ------------------------------------------ summary
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          MoneyRow('Sub total', _subTotal),
                          if (_tax > 0) MoneyRow('GST', _tax),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Expanded(child: Text('Discount')),
                              SizedBox(
                                width: 120,
                                child: TextField(
                                  controller: _discount,
                                  textAlign: TextAlign.right,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '0',
                                    prefixText: '₹ ',
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  onChanged: (_) => setState(_syncPaid),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          MoneyRow('Total', _grandTotal, bold: true),
                        ],
                      ),
                    ),
                  ),

                  // ------------------------------------------ payment
                  const SizedBox(height: 18),
                  const SectionHeader('Payment'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              const ButtonSegment(value: 'Cash', label: Text('Cash')),
                              const ButtonSegment(value: 'UPI', label: Text('UPI')),
                              const ButtonSegment(value: 'Card', label: Text('Card')),
                              ButtonSegment(
                                value: 'Credit',
                                label: const Text('Udhaar'),
                                enabled: !_isWalkIn,
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: (s) => setState(() {
                              _mode = s.first;
                              _paidTouched = true;
                              _paid.text = _mode == 'Credit'
                                  ? '0'
                                  : _grandTotal.toStringAsFixed(2);
                            }),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _paid,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Amount received now',
                              prefixText: '₹ ',
                              helperText: _balance > 0.009
                                  ? 'Udhaar of ${money(_balance)} will be added to the customer'
                                  : 'Bill fully paid',
                              helperStyle: TextStyle(
                                color: _balance > 0.009
                                    ? moneyNegative(context)
                                    : moneyPositive(context),
                                fontWeight: FontWeight.w600,
                              ),
                              suffixIcon: TextButton(
                                onPressed: () => setState(() {
                                  _paidTouched = true;
                                  if (_mode == 'Credit') _mode = 'Cash';
                                  _paid.text = _grandTotal.toStringAsFixed(2);
                                }),
                                child: const Text('Full'),
                              ),
                            ),
                            onChanged: (_) =>
                                setState(() => _paidTouched = true),
                          ),
                          if (problem != null) ...[
                            const SizedBox(height: 12),
                            _WarningBox(problem),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _notes,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional)',
                              prefixIcon: Icon(Icons.sticky_note_2_outlined),
                            ),
                          ),
                          const SizedBox(height: 6),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: _sendWhatsApp && !_isWalkIn,
                            onChanged: _isWalkIn
                                ? null
                                : (v) => setState(() => _sendWhatsApp = v),
                            secondary: const Icon(
                              Icons.chat_outlined,
                              color: Color(0xFF1FA855),
                            ),
                            title: const Text('Send bill on WhatsApp'),
                            subtitle: Text(
                              _customer == null
                                  ? 'Choose a customer first'
                                  : _isWalkIn
                                      ? 'Walk-in bill - share the invoice picture instead'
                                      : 'to +91 ${_customer!.mobile}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final Customer? customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = customer;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              c == null
                  ? CircleAvatar(
                      radius: 22,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        Icons.person_add_alt_1,
                        color: scheme.onPrimaryContainer,
                      ),
                    )
                  : InitialsAvatar(c.name, radius: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c?.name ?? 'Choose customer',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (c?.isTrusted == true) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified,
                            size: 16,
                            color: moneyPositive(context),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c == null ? 'Required - tap to pick' : '+91 ${c.mobile}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (c != null && c.outstandingBalance > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Already owes ${money(c.outstandingBalance)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: moneyNegative(context),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(
                c == null ? Icons.chevron_right : Icons.swap_horiz,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.onMinus,
    required this.onPlus,
    required this.onEditQty,
  });

  final _Line line;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEditQty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        line.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (line.productId == null) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.edit_note, size: 16, color: scheme.outline),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${money(line.price)} / ${line.unit}'
                  '${line.taxPercent > 0 ? '  +${qty(line.taxPercent)}%' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  money(line.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    line.quantity <= 1 ? Icons.delete_outline : Icons.remove,
                  ),
                  onPressed: onMinus,
                ),
                InkWell(
                  onTap: onEditQty,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 34),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    child: Text(
                      qty(line.quantity),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add),
                  onPressed: onPlus,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Check the bill" step: the whole bill as a list, with Edit (go back) or Confirm.
class _ConfirmBillSheet extends StatelessWidget {
  const _ConfirmBillSheet({
    required this.customer,
    required this.lines,
    required this.subTotal,
    required this.tax,
    required this.discount,
    required this.total,
    required this.paid,
    required this.balance,
    required this.mode,
    required this.notes,
    required this.sendWhatsApp,
  });

  final Customer customer;
  final List<_Line> lines;
  final double subTotal, tax, discount, total, paid, balance;
  final String mode;
  final String notes;
  final bool sendWhatsApp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              'Confirm bill',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Text('Check everything before it is saved and sent', style: muted),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                // customer
                Card(
                  child: ListTile(
                    leading: InitialsAvatar(customer.name),
                    title: Text(
                      customer.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text('+91 ${customer.mobile}'),
                    trailing: sendWhatsApp
                        ? const Icon(Icons.chat, color: Color(0xFF1FA855))
                        : null,
                  ),
                ),
                const SizedBox(height: 12),

                // item list
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < lines.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 13,
                            backgroundColor: scheme.surfaceContainerHighest,
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            lines[i].name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            '${qty(lines[i].quantity)} ${lines[i].unit} x ${money(lines[i].price)}'
                            '${lines[i].taxPercent > 0 ? '  +${qty(lines[i].taxPercent)}% GST' : ''}',
                          ),
                          trailing: Text(
                            money(lines[i].total),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // totals
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        MoneyRow('Sub total', subTotal),
                        if (tax > 0) MoneyRow('GST', tax),
                        if (discount > 0) MoneyRow('Discount', -discount),
                        const Divider(height: 20),
                        MoneyRow('Total', total, bold: true),
                        MoneyRow(
                          paid > 0 ? 'Paid now ($mode)' : 'Paid now',
                          paid,
                          tone: moneyPositive(context),
                        ),
                        if (balance > 0.009)
                          MoneyRow(
                            'Udhaar added',
                            balance,
                            bold: true,
                            tone: moneyNegative(context),
                          ),
                      ],
                    ),
                  ),
                ),
                if (notes.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text('Note: $notes', style: muted),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                  child: Text(
                    sendWhatsApp
                        ? 'After saving, WhatsApp opens with the bill for +91 ${customer.mobile}.'
                        : 'The bill will be saved without sending on WhatsApp.',
                    style: muted,
                  ),
                ),
              ],
            ),
          ),

          // Edit / Confirm
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context, true),
                      icon: Icon(
                        sendWhatsApp ? Icons.send_rounded : Icons.check_rounded,
                      ),
                      label: Text(
                        sendWhatsApp ? 'Confirm & send' : 'Confirm & save',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalBar extends StatelessWidget {
  const _TotalBar({
    required this.total,
    required this.items,
    required this.busy,
    required this.onSave,
  });

  final double total;
  final int items;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 16, 10),
          child: Row(
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$items item${items == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    money(total),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : onSave,
                  icon: busy
                      ? CoinLoader(size: 20)
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text(busy ? 'Saving...' : 'Review & send'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Searchable bottom sheet used to pick a customer or a product.
class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.searchOf,
    required this.tileBuilder,
    this.header,
  });

  final String title;
  final List<T> items;
  final String Function(T) searchOf;
  final Widget Function(T) tileBuilder;
  final Widget? header;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.items
        : widget.items
              .where(
                (e) => widget
                    .searchOf(e)
                    .toLowerCase()
                    .contains(_query.toLowerCase()),
              )
              .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            if (widget.header != null) ...[
              widget.header!,
              const Divider(height: 1),
            ],
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: 'Nothing matches',
                    )
                  : ListView.separated(
                      controller: controller,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => widget.tileBuilder(filtered[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
