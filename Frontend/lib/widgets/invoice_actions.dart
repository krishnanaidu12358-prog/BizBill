import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../services/invoice_pdf.dart';
import '../services/repo.dart';
import 'barcode_scanner.dart';
import 'common.dart';

/// The three ways a bill leaves the app. Shared by the owner's bill screen,
/// the post-save sheet and the customer's read-only view.
class InvoiceActions {
  /// Lets the owner pick how the bill goes out on WhatsApp: the colour invoice
  /// as a picture (default), the same design as a PDF, or the plain text message
  /// that opens straight in the customer's chat.
  static Future<void> sendWhatsApp(BuildContext context, Repo repo, Invoice inv) async {
    if (inv.isCancelled) {
      showSnack(context, 'Cancelled bills are not sent to customers.', error: true);
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFF1FA855),
                  foregroundColor: Colors.white,
                  child: Icon(Icons.chat),
                ),
                title: Text('Send ${inv.invoiceNumber} on WhatsApp',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${inv.customerName}  ·  +91 ${inv.customerMobile}  ·  '
                    '${money(inv.grandTotal)}'),
              ),
              const Divider(),
              _SendOption(
                icon: Icons.image_outlined,
                color: const Color(0xFF0F5C43),
                title: 'Colour invoice (picture)',
                subtitle: 'Table-style bill with colours. Shows as a photo in the chat.',
                recommended: true,
                onTap: () => Navigator.pop(ctx, 'image'),
              ),
              _SendOption(
                icon: Icons.picture_as_pdf_outlined,
                color: const Color(0xFFC62828),
                title: 'Colour invoice (PDF)',
                subtitle: 'Same design as a PDF file - best for printing.',
                onTap: () => Navigator.pop(ctx, 'pdf'),
              ),
              _SendOption(
                icon: Icons.notes,
                color: const Color(0xFF3949AB),
                title: 'Text message',
                subtitle: 'Opens the customer\'s chat directly with the bill as text.',
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    try {
      switch (choice) {
        case 'image':
          await InvoicePdf.shareImage(inv);
        case 'pdf':
          await InvoicePdf.share(inv);
        case 'text':
          final data = await repo.resendBill(inv.id);
          if (!context.mounted) return;
          await openWhatsApp(context, data['deepLink'] as String?);
      }
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not share the invoice: $e', error: true);
    }
  }

  static Future<void> sharePdf(BuildContext context, Invoice inv) async {
    try {
      await InvoicePdf.share(inv);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not create the PDF: $e', error: true);
    }
  }

  static const _kPrinterUrl = 'receipt_printer_url';
  static const _kPrinterName = 'receipt_printer_name';

  /// 80 mm till receipt. On Windows it goes straight to the saved receipt
  /// printer (chosen once); on a phone the system print sheet opens.
  static Future<void> printReceipt(BuildContext context, Invoice inv) async {
    try {
      if (isMobileDevice) {
        await InvoicePdf.printReceipt(inv);
        return;
      }
      var printer = await _savedPrinter();
      if (printer == null) {
        if (!context.mounted) return;
        printer = await chooseReceiptPrinter(context);
        if (printer == null) return;
      }
      await InvoicePdf.printReceipt(inv, printer: printer);
      if (context.mounted) showSnack(context, 'Receipt sent to ${printer.name}.');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not print the receipt: $e', error: true);
    }
  }

  static Future<Printer?> _savedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(_kPrinterUrl);
      if (url == null) return null;
      final printers = await Printing.listPrinters();
      for (final p in printers) {
        if (p.url == url && p.isAvailable) return p;
      }
    } catch (_) {
      // Fall through to asking again.
    }
    return null;
  }

  /// Lets the cashier pick the receipt printer once; it is remembered.
  static Future<Printer?> chooseReceiptPrinter(BuildContext context) async {
    final printer = await Printing.pickPrinter(
      context: context,
      title: 'Choose your receipt printer',
    );
    if (printer != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrinterUrl, printer.url);
      await prefs.setString(_kPrinterName, printer.name);
    }
    return printer;
  }

  static Future<void> printIt(BuildContext context, Invoice inv) async {
    try {
      await InvoicePdf.printIt(inv);
    } catch (e) {
      if (context.mounted) showSnack(context, 'Could not open printing: $e', error: true);
    }
  }
}

/// Sticky bottom bar with the bill's actions. Sits above the home indicator on iOS
/// and the gesture bar on Android.
class InvoiceActionBar extends StatefulWidget {
  const InvoiceActionBar({
    super.key,
    required this.invoice,
    this.repo,
    this.allowWhatsApp = true,
  });

  final Invoice invoice;

  /// Null for the customer view, which cannot trigger a WhatsApp send.
  final Repo? repo;
  final bool allowWhatsApp;

  @override
  State<InvoiceActionBar> createState() => _InvoiceActionBarState();
}

class _InvoiceActionBarState extends State<InvoiceActionBar> {
  String? _busy;

  Future<void> _run(String key, Future<void> Function() job) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      await job();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _spinner(Color c) => CoinLoader(size: 18);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inv = widget.invoice;
    final canWhatsApp =
        widget.allowWhatsApp && widget.repo != null && !inv.isCancelled;

    return Material(
      color: scheme.surface,
      elevation: 8,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (canWhatsApp) ...[
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1FA855),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy != null
                        ? null
                        : () => _run('wa',
                            () => InvoiceActions.sendWhatsApp(context, widget.repo!, inv)),
                    icon: _busy == 'wa' ? _spinner(Colors.white) : const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy != null
                      ? null
                      : () => _run('pdf', () => InvoiceActions.sharePdf(context, inv)),
                  icon: _busy == 'pdf'
                      ? _spinner(scheme.primary)
                      : const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 10),
              PopupMenuButton<String>(
                tooltip: 'Print',
                enabled: _busy == null,
                onSelected: (v) => _run('print', () async {
                  switch (v) {
                    case 'receipt':
                      await InvoiceActions.printReceipt(context, inv);
                    case 'a4':
                      await InvoiceActions.printIt(context, inv);
                    case 'printer':
                      await InvoiceActions.chooseReceiptPrinter(context);
                  }
                }),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'receipt',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.receipt_outlined),
                      title: Text('Receipt (80 mm thermal)'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'a4',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.description_outlined),
                      title: Text('A4 colour invoice'),
                    ),
                  ),
                  if (!isMobileDevice)
                    const PopupMenuItem(
                      value: 'printer',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Change receipt printer'),
                      ),
                    ),
                ],
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: _busy == 'print'
                      ? Center(child: _spinner(scheme.primary))
                      : Icon(Icons.print_outlined, color: scheme.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendOption extends StatelessWidget {
  const _SendOption({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.recommended = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color),
      ),
      title: Row(
        children: [
          Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (recommended) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1FA855).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('Best',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1B7F3B))),
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5)),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}
