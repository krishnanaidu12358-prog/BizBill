import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/barcode_scanner.dart';
import '../../widgets/common.dart';

class OwnerProductsTab extends StatefulWidget {
  const OwnerProductsTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<OwnerProductsTab> createState() => _OwnerProductsTabState();
}

class _OwnerProductsTabState extends State<OwnerProductsTab> {
  final _search = TextEditingController();
  bool _lowOnly = false;
  late Future<List<Product>> _future = widget.repo.products();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.repo.products(
          search: _search.text.trim().isEmpty ? null : _search.text.trim(),
          lowStockOnly: _lowOnly ? true : null,
        ));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _edit([Product? product]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductFormSheet(repo: widget.repo, existing: product),
    );
    if (saved == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Search name, SKU or scan a barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isMobileDevice)
                      IconButton(
                        tooltip: 'Scan barcode',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: () async {
                          final code = await scanBarcodeWithCamera(context);
                          if (code != null) {
                            _search.text = code;
                            await _reload();
                          }
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: _reload,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Low stock only'),
                  selected: _lowOnly,
                  onSelected: (v) {
                    setState(() => _lowOnly = v);
                    _reload();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AsyncBody<List<Product>>(
              future: _future,
              onRefresh: _reload,
              builder: (context, list) {
                if (list.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'No products',
                        subtitle: 'Add your first product with the + button',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final p = list[i];
                    return Card(
                      child: ListTile(
                        title: Text(p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${p.sku ?? 'No SKU'}'
                          '${p.taxPercent > 0 ? '  -  GST ${qty(p.taxPercent)}%' : ''}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(money(p.sellingPrice),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            const SizedBox(height: 2),
                            Text(
                              '${qty(p.stockQty)} ${p.unit}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    p.isLowStock ? FontWeight.w700 : FontWeight.w400,
                                color: p.isLowStock
                                    ? moneyWarning(context)
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _edit(p),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addProduct',
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Product'),
      ),
    );
  }
}

class _ProductFormSheet extends StatefulWidget {
  const _ProductFormSheet({required this.repo, this.existing});

  final Repo repo;
  final Product? existing;

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _sku = TextEditingController(text: widget.existing?.sku ?? '');
  late final _barcode = TextEditingController(text: widget.existing?.barcode ?? '');
  late final _unit = TextEditingController(text: widget.existing?.unit ?? 'PCS');
  late final _price = TextEditingController(
      text: (widget.existing?.sellingPrice ?? 0).toStringAsFixed(2));
  late final _tax = TextEditingController(
      text: (widget.existing?.taxPercent ?? 0).toStringAsFixed(0));
  late final _stock = TextEditingController(
      text: (widget.existing?.stockQty ?? 0).toStringAsFixed(0));
  late final _minStock = TextEditingController(
      text: (widget.existing?.minStockQty ?? 0).toStringAsFixed(0));
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _sku, _barcode, _unit, _price, _tax, _stock, _minStock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);

    final body = {
      'name': _name.text.trim(),
      'sku': _sku.text.trim().isEmpty ? null : _sku.text.trim(),
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'unit': _unit.text.trim().isEmpty ? 'PCS' : _unit.text.trim(),
      'sellingPrice': double.tryParse(_price.text) ?? 0,
      'purchasePrice': 0,
      'taxPercent': double.tryParse(_tax.text) ?? 0,
      'stockQty': double.tryParse(_stock.text) ?? 0,
      'minStockQty': double.tryParse(_minStock.text) ?? 0,
    };

    try {
      final msg = _isEdit
          ? await widget.repo.updateProduct(widget.existing!.id, body)
          : await widget.repo.createProduct(body);
      if (!mounted) return;
      showSnack(context, msg);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit product' : 'Add product',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Product name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter the product name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcode,
                decoration: InputDecoration(
                  labelText: 'Barcode',
                  hintText: isMobileDevice
                      ? 'Tap the camera to scan the pack'
                      : 'Click here and scan the pack with the scanner',
                  prefixIcon: const Icon(Icons.qr_code_scanner),
                  suffixIcon: isMobileDevice
                      ? IconButton(
                          tooltip: 'Scan with camera',
                          icon: const Icon(Icons.photo_camera_outlined),
                          onPressed: () async {
                            final code = await scanBarcodeWithCamera(context);
                            if (code != null) setState(() => _barcode.text = code);
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _sku,
                      decoration: const InputDecoration(labelText: 'SKU'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 100,
                    child: TextFormField(
                      controller: _unit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Selling price', prefixText: '₹ '),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextFormField(
                      controller: _tax,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'GST', suffixText: '%'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _stock,
                      enabled: !_isEdit,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Stock quantity',
                        helperText: _isEdit ? 'Change via bills only' : null,
                        helperMaxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minStock,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Low stock alert at'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? CoinLoader(size: 22)
                    : Text(_isEdit ? 'Save changes' : 'Add product'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

