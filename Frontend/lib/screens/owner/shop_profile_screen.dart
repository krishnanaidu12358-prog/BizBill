import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../../core/api_client.dart';
import '../../models/models.dart';
import '../../services/branding_images.dart';
import '../../services/invoice_pdf.dart';
import '../../services/repo.dart';
import '../../widgets/branding_image.dart';
import '../../widgets/common.dart';

/// Shop profile and bill design: name, type (supermarket, mart, kirana ...),
/// address, GSTIN, logo, signature and the lines printed on bills and receipts.
/// Used by the owner for their shop, and by the Super Admin for any shop.
class ShopProfileScreen extends StatefulWidget {
  const ShopProfileScreen({super.key, required this.repo, this.adminView = false});

  final Repo repo;
  final bool adminView;

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  final _form = GlobalKey<FormState>();
  BusinessProfile? _p;
  String? _error;
  bool _saving = false;
  bool _dirty = false;

  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _owner = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();
  final _gst = TextEditingController();
  final _prefix = TextEditingController();
  final _signatory = TextEditingController();
  final _terms = TextEditingController();
  final _footer = TextEditingController();
  String _type = 'Retail';
  bool _logoOnReceipt = true;
  bool _showSignature = true;

  List<TextEditingController> get _all => [
        _name, _tagline, _owner, _email, _address, _city, _state, _pincode, _gst, _prefix,
        _signatory, _terms, _footer,
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final p = await widget.repo.businessProfile();
      if (!mounted) return;
      _apply(p);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _apply(BusinessProfile p) {
    setState(() {
      _p = p;
      _name.text = p.name;
      _tagline.text = p.tagline ?? '';
      _owner.text = p.ownerName ?? '';
      _email.text = p.email ?? '';
      _address.text = p.addressLine ?? '';
      _city.text = p.city ?? '';
      _state.text = p.state ?? '';
      _pincode.text = p.pincode ?? '';
      _gst.text = p.gstNumber ?? '';
      _prefix.text = p.invoicePrefix;
      _signatory.text = p.signatoryName ?? '';
      _terms.text = p.invoiceTerms ?? '';
      _footer.text = p.receiptFooter ?? '';
      _type = p.businessTypes.contains(p.businessType) ? p.businessType : 'Retail';
      _logoOnReceipt = p.showLogoOnReceipt;
      _showSignature = p.showSignature;
      _dirty = false;
    });
  }

  String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, dynamic> _body() => {
        'name': _name.text.trim(),
        'businessType': _type,
        'tagline': _t(_tagline),
        'ownerName': _t(_owner),
        'email': _t(_email),
        'addressLine': _t(_address),
        'city': _t(_city),
        'state': _t(_state),
        'pincode': _t(_pincode),
        'gstNumber': _t(_gst)?.toUpperCase(),
        'invoicePrefix': _prefix.text.trim().toUpperCase(),
        'signatoryName': _t(_signatory),
        'invoiceTerms': _t(_terms),
        'receiptFooter': _t(_footer),
        'showLogoOnReceipt': _logoOnReceipt,
        'showSignature': _showSignature,
      };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final res = await widget.repo.saveBusinessProfile(_body());
      if (!mounted) return;
      _apply(BusinessProfile.fromJson(res.data as Map<String, dynamic>));
      showSnack(context, res.message);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------- images

  Future<void> _pick(String kind) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: kind == 'logo' ? 800 : 1000,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await _upload(kind, bytes, file.name);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the picture: $e', error: true);
    }
  }

  Future<void> _upload(String kind, List<int> bytes, String name) async {
    setState(() => _saving = true);
    try {
      final p = await widget.repo.uploadBranding(kind, bytes, name);
      BrandingImages.clear();
      if (!mounted) return;
      final dirty = _dirty;
      _apply(p);
      _dirty = dirty;
      showSnack(context, kind == 'logo' ? 'Logo saved.' : 'Signature saved.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(String kind) async {
    try {
      final p = await widget.repo.removeBranding(kind);
      BrandingImages.clear();
      if (!mounted) return;
      _apply(p);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _drawSignature() async {
    final png = await showDialog<Uint8List>(context: context, builder: (_) => const _SignaturePad());
    if (png != null) await _upload('signature', png, 'signature.png');
  }

  // ------------------------------------------------------------ preview

  Invoice _sample() {
    final p = _p!;
    final addr = [_t(_address), _t(_city), _t(_state), _t(_pincode)].whereType<String>().join(', ');
    return Invoice(
      id: 0,
      invoiceNumber: '${_prefix.text.trim().toUpperCase()}-0001',
      invoiceDate: DateTime.now().toUtc().toIso8601String(),
      businessName: _name.text.trim(),
      businessId: p.id,
      businessMobile: p.mobile,
      businessAddress: addr.isEmpty ? null : addr,
      businessGstNumber: _t(_gst),
      businessTagline: _t(_tagline),
      businessEmail: _t(_email),
      businessType: _type,
      logoUrl: p.logoUrl,
      signatureUrl: p.signatureUrl,
      signatoryName: _t(_signatory),
      invoiceTerms: _t(_terms),
      receiptFooter: _t(_footer),
      showLogoOnReceipt: _logoOnReceipt,
      showSignature: _showSignature,
      customerId: 0,
      customerName: 'Sample Customer',
      customerMobile: '9876543210',
      subTotal: 250,
      discountAmount: 0,
      taxAmount: 12.5,
      grandTotal: 262.5,
      paidAmount: 262.5,
      balanceAmount: 0,
      paymentMode: 'Cash',
      status: 'Paid',
      billedByName: 'Cashier',
      items: [
        InvoiceItem(productName: 'Basmati Rice 1kg', quantity: 1, unitPrice: 150, taxPercent: 5, lineTotal: 157.5, taxAmount: 7.5),
        InvoiceItem(productName: 'Sunflower Oil 1L', quantity: 1, unitPrice: 100, taxPercent: 5, lineTotal: 105, taxAmount: 5),
      ],
    );
  }

  void _preview() {
    final inv = _sample();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Bill preview'),
              bottom: const TabBar(tabs: [Tab(text: 'A4 invoice'), Tab(text: 'Till receipt (80 mm)')]),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                PdfPreview(
                  build: (_) => InvoicePdf.build(inv),
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'preview.pdf',
                ),
                PdfPreview(
                  build: (_) => InvoicePdf.buildReceipt(inv),
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  pdfFileName: 'receipt-preview.pdf',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _p;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Leave without saving?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Leave')),
            ],
          ),
        );
        if (leave == true && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.adminView ? 'Shop profile (admin)' : 'Shop profile & bill design'),
          actions: [
            if (p != null)
              TextButton.icon(
                onPressed: _preview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Preview bill'),
              ),
          ],
        ),
        floatingActionButton: p == null
            ? null
            : FloatingActionButton.extended(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_outlined),
                label: Text(_dirty ? 'Save changes' : 'Save'),
              ),
        body: _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : p == null
                ? const Center(child: CoinLoader())
                : Form(
                    key: _form,
                    onChanged: () {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    child: ResponsiveCenter(
                      maxWidth: 820,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                        children: [
                          // -------------------------------------------- branding
                          SectionHeader('Logo & signature',
                              subtitle: 'Printed on every bill and receipt. PNG or JPG.'),
                          LayoutBuilder(builder: (context, c) {
                            final wide = c.maxWidth > 560;
                            final logoCard = _ImageCard(
                              title: 'Shop logo',
                              url: p.logoUrl,
                              icon: Icons.storefront_outlined,
                              busy: _saving,
                              actions: [
                                FilledButton.tonalIcon(
                                  onPressed: _saving ? null : () => _pick('logo'),
                                  icon: const Icon(Icons.upload_outlined),
                                  label: Text(p.logoUrl == null ? 'Upload logo' : 'Change'),
                                ),
                                if (p.logoUrl != null)
                                  TextButton(onPressed: () => _remove('logo'), child: const Text('Remove')),
                              ],
                            );
                            final signCard = _ImageCard(
                              title: 'Signature',
                              url: p.signatureUrl,
                              icon: Icons.draw_outlined,
                              busy: _saving,
                              actions: [
                                FilledButton.tonalIcon(
                                  onPressed: _saving ? null : () => _pick('signature'),
                                  icon: const Icon(Icons.upload_outlined),
                                  label: const Text('Upload'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _saving ? null : _drawSignature,
                                  icon: const Icon(Icons.gesture),
                                  label: const Text('Draw'),
                                ),
                                if (p.signatureUrl != null)
                                  TextButton(onPressed: () => _remove('signature'), child: const Text('Remove')),
                              ],
                            );
                            return wide
                                ? Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [Expanded(child: logoCard), const SizedBox(width: 10), Expanded(child: signCard)],
                                  )
                                : Column(children: [logoCard, signCard]);
                          }),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Logo on till receipts'),
                            subtitle: const Text('Turn off if your thermal printer prints it too dark'),
                            value: _logoOnReceipt,
                            onChanged: (v) => setState(() {
                              _logoOnReceipt = v;
                              _dirty = true;
                            }),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Signature on invoices'),
                            value: _showSignature,
                            onChanged: (v) => setState(() {
                              _showSignature = v;
                              _dirty = true;
                            }),
                          ),

                          // -------------------------------------------- shop
                          SectionHeader('Shop details'),
                          _field(_name, 'Shop name', icon: Icons.store_outlined, required: true),
                          DropdownButtonFormField<String>(
                            value: _type,
                            decoration: const InputDecoration(
                                labelText: 'Business type', prefixIcon: Icon(Icons.category_outlined)),
                            items: [
                              for (final t in p.businessTypes) DropdownMenuItem(value: t, child: Text(t)),
                            ],
                            onChanged: (v) => setState(() {
                              _type = v ?? _type;
                              _dirty = true;
                            }),
                          ),
                          const SizedBox(height: 12),
                          _field(_tagline, 'Tagline (optional)',
                              icon: Icons.short_text, hint: 'e.g. Fresh groceries at best prices'),
                          _field(_owner, 'Owner name', icon: Icons.person_outline),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                  labelText: 'Phone on bills (login mobile)', prefixIcon: Icon(Icons.phone_outlined)),
                              child: Text('+91 ${p.mobile}'),
                            ),
                          ),
                          _field(_email, 'Email', icon: Icons.email_outlined, keyboard: TextInputType.emailAddress),

                          // -------------------------------------------- address
                          SectionHeader('Address'),
                          _field(_address, 'Door no, street, area', icon: Icons.home_outlined, lines: 2),
                          Row(
                            children: [
                              Expanded(child: _field(_city, 'City')),
                              const SizedBox(width: 10),
                              Expanded(child: _field(_state, 'State')),
                            ],
                          ),
                          _field(_pincode, 'Pincode',
                              keyboard: TextInputType.number,
                              formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                              validator: (v) => (v ?? '').isEmpty || RegExp(r'^\d{6}$').hasMatch(v!)
                                  ? null
                                  : '6 digits'),

                          // -------------------------------------------- tax & bills
                          SectionHeader('Tax & bill numbers'),
                          _field(_gst, 'GSTIN (optional)',
                              icon: Icons.receipt_outlined,
                              caps: TextCapitalization.characters,
                              validator: (v) => (v ?? '').trim().isEmpty ||
                                      RegExp(r'^[0-9]{2}[A-Z0-9]{13}$').hasMatch(v!.trim().toUpperCase())
                                  ? null
                                  : '15 characters, e.g. 36ABCDE1234F1Z5'),
                          _field(_prefix, 'Bill number prefix',
                              icon: Icons.tag,
                              caps: TextCapitalization.characters,
                              hint: 'e.g. KKS makes KKS-00001',
                              validator: (v) =>
                                  RegExp(r'^[A-Za-z0-9]{1,10}$').hasMatch((v ?? '').trim()) ? null : '1-10 letters or digits'),

                          // -------------------------------------------- printing
                          SectionHeader('Printed text'),
                          _field(_signatory, 'Name under the signature',
                              icon: Icons.badge_outlined, hint: 'e.g. K. Reddy, Proprietor'),
                          _field(_terms, 'Terms & conditions (A4 invoice)',
                              lines: 4,
                              hint: '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.'),
                          _field(_footer, 'Last line of the till receipt', icon: Icons.favorite_border, hint: 'Thank you! Visit again.'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _preview,
                            icon: const Icon(Icons.visibility_outlined),
                            label: const Text('Preview how bills will print'),
                          ),
                          if (_dirty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text('Preview shows your changes; save to use them on real bills.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: scheme.outline)),
                            ),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    IconData? icon,
    String? hint,
    int lines = 1,
    bool required = false,
    TextInputType? keyboard,
    TextCapitalization caps = TextCapitalization.sentences,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          minLines: 1,
          keyboardType: keyboard ?? (lines > 1 ? TextInputType.multiline : null),
          textCapitalization: caps,
          inputFormatters: formatters,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: icon == null ? null : Icon(icon),
            alignLabelWithHint: lines > 1,
          ),
          validator: validator ?? (required ? (v) => (v ?? '').trim().isEmpty ? 'Required' : null : null),
        ),
      );
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.title,
    required this.url,
    required this.icon,
    required this.actions,
    this.busy = false,
  });

  final String title;
  final String? url;
  final IconData icon;
  final List<Widget> actions;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              height: 110,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: BrandingImage(
                key: ValueKey(url),
                url: url,
                width: 220,
                height: 100,
                placeholder: Icon(icon, size: 40, color: scheme.outlineVariant),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: actions),
          ],
        ),
      ),
    );
  }
}

/// Sign with a finger (phone) or mouse (Windows). Returns a transparent PNG.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad();

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];
  static const _size = Size(500, 200);

  Future<void> _done() async {
    if (_strokes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _SignaturePainter(_strokes, scale: 2).paint(canvas, _size * 2);
    final img = await recorder.endRecording().toImage((_size.width * 2).toInt(), (_size.height * 2).toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (mounted) Navigator.pop(context, data!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign here'),
      content: FittedBox(
        child: Container(
          width: _size.width,
          height: _size.height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRect(
            child: GestureDetector(
              onPanStart: (d) => setState(() => _strokes.add([d.localPosition])),
              onPanUpdate: (d) => setState(() => _strokes.last.add(d.localPosition)),
              child: CustomPaint(painter: _SignaturePainter(_strokes), size: _size),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => setState(_strokes.clear), child: const Text('Clear')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: const Text('Use signature')),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, {this.scale = 1});

  final List<List<Offset>> strokes;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0B2A6F)
      ..strokeWidth = 2.6 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      final path = Path()..moveTo(s.first.dx * scale, s.first.dy * scale);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx * scale, p.dy * scale);
      }
      if (s.length == 1) {
        canvas.drawCircle(s.first * scale, 1.3 * scale, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
