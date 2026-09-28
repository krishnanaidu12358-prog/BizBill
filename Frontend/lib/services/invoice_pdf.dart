import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../models/proof_models.dart';
import 'branding_images.dart';

/// A colourful, table-style tax invoice built on the phone from the bill the API
/// returned. The same design is used for the PDF, the print preview and the
/// image that is shared on WhatsApp.
///
/// Amounts use "Rs." rather than the rupee sign: the PDF's built-in fonts have
/// no glyph for it, and a bundled font would add ~300 KB to every install.
class InvoicePdf {
  static final _num = NumberFormat('#,##,##0.00', 'en_IN');
  static final _dateOnly = DateFormat('dd MMM yyyy');
  static final _time = DateFormat('hh:mm a');

  static String _rs(num v) => 'Rs. ${_num.format(v)}';
  static String _qty(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(3);

  // ------------------------------------------------------------- colours
  static const _brand = PdfColor.fromInt(0xFF0F5C43); // deep green
  static const _brandMid = PdfColor.fromInt(0xFF1B7F5B);
  static const _brandSoft = PdfColor.fromInt(0xFFE7F4EE); // zebra rows / cards
  static const _accent = PdfColor.fromInt(0xFFF2A516); // amber stripe
  static const _accentSoft = PdfColor.fromInt(0xFFFFF4DC);
  static const _ink = PdfColor.fromInt(0xFF1F2937);
  static const _muted = PdfColor.fromInt(0xFF6B7280);
  static const _line = PdfColor.fromInt(0xFFCFE3D8);
  static const _danger = PdfColor.fromInt(0xFFC62828);
  static const _dangerSoft = PdfColor.fromInt(0xFFFDECEA);
  static const _success = PdfColor.fromInt(0xFF1B7F3B);
  static const _successSoft = PdfColor.fromInt(0xFFE6F4EA);
  static const _white = PdfColors.white;
  static const _whiteDim = PdfColor.fromInt(0xFFD7EDE3);

  static String fileName(Invoice inv) =>
      'Invoice-${inv.invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')}.pdf';

  static String imageName(Invoice inv, [int page = 1, int pages = 1]) =>
      'Invoice-${inv.invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_')}'
      '${pages > 1 ? '-p$page' : ''}.png';

  /// [fitToContent] makes one page exactly as tall as the bill (used for the
  /// WhatsApp picture, so a short bill is not half empty white space).
  static Future<Uint8List> build(Invoice inv, {bool fitToContent = false}) async {
    final doc = pw.Document(
      title: 'Invoice ${inv.invoiceNumber}',
      author: inv.businessName,
      creator: 'BizBill',
    );

    final date = DateTime.tryParse(inv.invoiceDate)?.toLocal();
    final hasGst = inv.taxAmount > 0;
    final hasItemDiscount = inv.items.any((i) => i.discountAmount > 0);

    // Shop's own logo and signature, from the shop profile.
    final logoBytes = await BrandingImages.load(inv.logoUrl);
    final signBytes = inv.showSignature ? await BrandingImages.load(inv.signatureUrl) : null;
    final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
    final signature = signBytes == null ? null : pw.MemoryImage(signBytes);

    // Scan-to-pay QR for the balance, when the shop has set up UPI.
    final payLink = (inv.businessUpiId ?? '').isNotEmpty &&
            inv.balanceAmount > 0 &&
            !inv.isCancelled
        ? ShopUpi(
            businessId: inv.businessId,
            businessName: inv.businessName,
            upiId: inv.businessUpiId,
            upiName: inv.businessUpiName ?? inv.businessName,
          ).payLink(amount: inv.balanceAmount, note: 'Bill ${inv.invoiceNumber}')
        : null;

    final statusText = inv.isCancelled
        ? 'CANCELLED'
        : inv.balanceAmount > 0
            ? (inv.paidAmount > 0 ? 'PARTLY PAID' : 'UNPAID')
            : 'PAID';
    final statusBg = inv.isCancelled
        ? const PdfColor.fromInt(0xFFE5E7EB)
        : inv.balanceAmount > 0
            ? _dangerSoft
            : _successSoft;
    final statusFg = inv.isCancelled
        ? _muted
        : inv.balanceAmount > 0
            ? _danger
            : _success;

    // --------------------------------------------------------- helpers
    pw.Widget label(String t, {PdfColor color = _brandMid}) => pw.Text(t,
        style: pw.TextStyle(
            fontSize: 8, fontWeight: pw.FontWeight.bold, color: color, letterSpacing: 0.8));

    pw.Widget infoLine(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2.5),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 58,
                child: pw.Text(k, style: const pw.TextStyle(fontSize: 9, color: _muted)),
              ),
              pw.Expanded(
                child: pw.Text(v,
                    style: pw.TextStyle(
                        fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: _ink)),
              ),
            ],
          ),
        );

    pw.Widget card({required pw.Widget child, PdfColor bg = _brandSoft}) => pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 11),
          decoration: pw.BoxDecoration(
            color: bg,
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: _line, width: 0.8),
          ),
          child: child,
        );

    pw.Widget cell(String t,
            {pw.TextAlign align = pw.TextAlign.left,
            bool bold = false,
            PdfColor color = _ink,
            double size = 9.5}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: pw.Text(t,
              textAlign: align,
              style: pw.TextStyle(
                  fontSize: size,
                  color: color,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    pw.Widget head(String t, {pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: pw.Text(t,
              textAlign: align,
              style: pw.TextStyle(
                  fontSize: 8.5,
                  color: _white,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 0.4)),
        );

    pw.Widget totalRow(String l, String v,
            {PdfColor? bg, PdfColor color = _ink, bool bold = false, double size = 9.5}) =>
        pw.Container(
          color: bg,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(l,
                  style: pw.TextStyle(
                      fontSize: size,
                      color: color,
                      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text(v,
                  style: pw.TextStyle(
                      fontSize: size,
                      color: color,
                      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );

    // ------------------------------------------------------ item table
    final cols = <_Col>[
      _Col('#', const pw.FixedColumnWidth(24), pw.TextAlign.center),
      _Col('ITEM DESCRIPTION', const pw.FlexColumnWidth(4.2), pw.TextAlign.left),
      _Col('QTY', const pw.FlexColumnWidth(1.1), pw.TextAlign.right),
      _Col('RATE', const pw.FlexColumnWidth(1.7), pw.TextAlign.right),
      if (hasItemDiscount) _Col('DISC.', const pw.FlexColumnWidth(1.4), pw.TextAlign.right),
      if (hasGst) _Col('GST %', const pw.FlexColumnWidth(1.1), pw.TextAlign.right),
      if (hasGst) _Col('GST AMT', const pw.FlexColumnWidth(1.5), pw.TextAlign.right),
      _Col('AMOUNT', const pw.FlexColumnWidth(1.9), pw.TextAlign.right),
    ];

    List<String> rowValues(int i) {
      final it = inv.items[i];
      return [
        '${i + 1}',
        it.productName,
        _qty(it.quantity),
        _num.format(it.unitPrice),
        if (hasItemDiscount) it.discountAmount > 0 ? _num.format(it.discountAmount) : '-',
        if (hasGst) it.taxPercent > 0 ? '${_qty(it.taxPercent)}%' : '-',
        if (hasGst) it.taxAmount > 0 ? _num.format(it.taxAmount) : '-',
        _num.format(it.lineTotal),
      ];
    }

    final totalQty = inv.items.fold<double>(0, (s, i) => s + i.quantity);
    final totalItemTax = inv.items.fold<double>(0, (s, i) => s + i.taxAmount);
    final totalItemDisc = inv.items.fold<double>(0, (s, i) => s + i.discountAmount);
    final totalLines = inv.items.fold<double>(0, (s, i) => s + i.lineTotal);

    final itemsTable = pw.Table(
      border: pw.TableBorder.all(color: _line, width: 0.7),
      columnWidths: {for (var c = 0; c < cols.length; c++) c: cols[c].width},
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _brand),
          children: [for (final c in cols) head(c.title, align: c.align)],
        ),
        for (var i = 0; i < inv.items.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(color: i.isOdd ? _brandSoft : _white),
            children: [
              for (var c = 0; c < cols.length; c++)
                cell(rowValues(i)[c],
                    align: cols[c].align,
                    bold: c == 1 || c == cols.length - 1,
                    color: c == 0 ? _muted : _ink),
            ],
          ),
        // Column totals, so the table adds up on its own.
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _accentSoft),
          children: [
            cell(''),
            cell('Total (${inv.items.length} item${inv.items.length == 1 ? '' : 's'})',
                bold: true),
            cell(_qty(totalQty), align: pw.TextAlign.right, bold: true),
            cell(''),
            if (hasItemDiscount)
              cell(_num.format(totalItemDisc), align: pw.TextAlign.right, bold: true),
            if (hasGst) cell(''),
            if (hasGst) cell(_num.format(totalItemTax), align: pw.TextAlign.right, bold: true),
            cell(_num.format(totalLines), align: pw.TextAlign.right, bold: true),
          ],
        ),
      ],
    );

    pw.Widget footerFor(int page, int pages) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _line, width: 0.7))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${inv.businessName}  |  ${inv.invoiceNumber}',
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
              pw.Text('Page $page of $pages  |  Generated with BizBill',
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            ],
          ),
        );

    final content = <pw.Widget>[
          // ------------------------------------------------ header band
          pw.Container(
            decoration: pw.BoxDecoration(
              gradient: const pw.LinearGradient(
                colors: [_brand, _brandMid],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null) ...[
                  pw.Container(
                    width: 66,
                    height: 66,
                    padding: const pw.EdgeInsets.all(5),
                    decoration: pw.BoxDecoration(
                      color: _white,
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Image(logo, fit: pw.BoxFit.contain),
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(inv.businessName,
                          style: pw.TextStyle(
                              fontSize: 20, fontWeight: pw.FontWeight.bold, color: _white)),
                      if ((inv.businessTagline ?? '').isNotEmpty)
                        pw.Text(inv.businessTagline!,
                            style: pw.TextStyle(
                                fontSize: 9.5, fontStyle: pw.FontStyle.italic, color: _whiteDim)),
                      pw.SizedBox(height: 4),
                      if ((inv.businessAddress ?? '').isNotEmpty)
                        pw.Text(inv.businessAddress!,
                            style: const pw.TextStyle(fontSize: 9, color: _whiteDim)),
                      if (inv.businessMobile.isNotEmpty || (inv.businessEmail ?? '').isNotEmpty)
                        pw.Text(
                            [
                              if (inv.businessMobile.isNotEmpty) 'Phone: +91 ${inv.businessMobile}',
                              if ((inv.businessEmail ?? '').isNotEmpty) inv.businessEmail!,
                            ].join('   |   '),
                            style: const pw.TextStyle(fontSize: 9, color: _whiteDim)),
                      if ((inv.businessGstNumber ?? '').isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: pw.Text('GSTIN: ${inv.businessGstNumber}',
                              style: pw.TextStyle(
                                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: _white)),
                        ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(hasGst ? 'TAX INVOICE' : 'INVOICE',
                        style: pw.TextStyle(
                            fontSize: 17,
                            fontWeight: pw.FontWeight.bold,
                            color: _white,
                            letterSpacing: 1.5)),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: pw.BoxDecoration(
                        color: _accent,
                        borderRadius: pw.BorderRadius.circular(12),
                      ),
                      child: pw.Text(inv.invoiceNumber,
                          style: pw.TextStyle(
                              fontSize: 10, fontWeight: pw.FontWeight.bold, color: _ink)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(height: 3, margin: const pw.EdgeInsets.symmetric(horizontal: 14),
              color: _accent),
          pw.SizedBox(height: 14),

          // ------------------------------------------------ info cards
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 5,
                child: card(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      label('BILL TO'),
                      pw.SizedBox(height: 4),
                      pw.Text(inv.customerName,
                          style: pw.TextStyle(
                              fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _ink)),
                      pw.SizedBox(height: 2),
                      pw.Text('+91 ${inv.customerMobile}',
                          style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
                      if ((inv.customerAddress ?? '').isNotEmpty)
                        pw.Text(inv.customerAddress!,
                            style: const pw.TextStyle(fontSize: 9, color: _muted)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 5,
                child: card(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      label('INVOICE DETAILS'),
                      pw.SizedBox(height: 2),
                      infoLine('Invoice no', inv.invoiceNumber),
                      if (date != null) infoLine('Date', _dateOnly.format(date)),
                      if (date != null) infoLine('Time', _time.format(date)),
                      infoLine('Payment',
                          inv.paymentMode == 'Credit' ? 'Udhaar (credit)' : inv.paymentMode),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                flex: 3,
                child: pw.Container(
                  padding: const pw.EdgeInsets.fromLTRB(10, 10, 10, 11),
                  decoration: pw.BoxDecoration(
                    color: statusBg,
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: statusFg, width: 1),
                  ),
                  child: pw.Column(
                    children: [
                      label('STATUS', color: statusFg),
                      pw.SizedBox(height: 6),
                      pw.Text(statusText,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              fontSize: 13, fontWeight: pw.FontWeight.bold, color: statusFg)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                          inv.balanceAmount > 0 && !inv.isCancelled
                              ? 'Due ${_rs(inv.balanceAmount)}'
                              : _rs(inv.grandTotal),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // ------------------------------------------------ items
          itemsTable,
          pw.SizedBox(height: 14),

          // ------------------------------------------------ words + totals
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    card(
                      bg: _accentSoft,
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          label('AMOUNT IN WORDS', color: const PdfColor.fromInt(0xFF9A6700)),
                          pw.SizedBox(height: 4),
                          pw.Text(amountInWords(inv.grandTotal),
                              style: pw.TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: _ink,
                                  fontStyle: pw.FontStyle.italic)),
                        ],
                      ),
                    ),
                    if ((inv.notes ?? '').isNotEmpty) ...[
                      pw.SizedBox(height: 8),
                      card(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            label('NOTE'),
                            pw.SizedBox(height: 4),
                            pw.Text(inv.notes!,
                                style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
                          ],
                        ),
                      ),
                    ],
                    if (payLink != null) ...[
                      pw.SizedBox(height: 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          color: _white,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: _brandMid, width: 1.2),
                        ),
                        child: pw.Row(
                          children: [
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: payLink,
                              width: 78,
                              height: 78,
                              color: _ink,
                            ),
                            pw.SizedBox(width: 12),
                            pw.Expanded(
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  label('SCAN TO PAY BY UPI'),
                                  pw.SizedBox(height: 4),
                                  pw.Text(_rs(inv.balanceAmount),
                                      style: pw.TextStyle(
                                          fontSize: 13,
                                          fontWeight: pw.FontWeight.bold,
                                          color: _brand)),
                                  pw.SizedBox(height: 2),
                                  pw.Text(inv.businessUpiName ?? inv.businessName,
                                      style: pw.TextStyle(
                                          fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
                                  pw.Text(inv.businessUpiId!,
                                      style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
                                  pw.SizedBox(height: 3),
                                  pw.Text('Google Pay / PhonePe / Paytm / BHIM',
                                      style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Container(
                width: 230,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.ClipRRect(
                  horizontalRadius: 8,
                  verticalRadius: 8,
                  child: pw.Column(
                    children: [
                      pw.SizedBox(height: 4),
                      totalRow('Sub total', _rs(inv.subTotal)),
                      if (inv.discountAmount > 0)
                        totalRow('Discount', '- ${_rs(inv.discountAmount)}',
                            color: _success),
                      if (hasGst) totalRow('GST', '+ ${_rs(inv.taxAmount)}'),
                      pw.SizedBox(height: 4),
                      totalRow('GRAND TOTAL', _rs(inv.grandTotal),
                          bg: _brand, color: _white, bold: true, size: 12),
                      totalRow('Paid', _rs(inv.paidAmount),
                          bg: _successSoft, color: _success, bold: true),
                      if (inv.balanceAmount > 0)
                        totalRow('Balance due', _rs(inv.balanceAmount),
                            bg: _dangerSoft, color: _danger, bold: true, size: 11),
                    ],
                  ),
                ),
              ),
            ],
          ),

          if (!inv.isCancelled && inv.customerOutstanding > inv.balanceAmount + 0.009) ...[
            pw.SizedBox(height: 12),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: pw.BoxDecoration(
                color: _dangerSoft,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: _danger, width: 0.8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total outstanding with ${inv.businessName} (all bills)',
                      style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
                  pw.Text(_rs(inv.customerOutstanding),
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold, color: _danger)),
                ],
              ),
            ),
          ],

          // ------------------------------------------------ sign-off
          pw.SizedBox(height: 26),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  decoration: pw.BoxDecoration(
                    color: _brandSoft,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      if ((inv.invoiceTerms ?? '').isNotEmpty) ...[
                        label('TERMS & CONDITIONS'),
                        pw.SizedBox(height: 3),
                        pw.Text(inv.invoiceTerms!,
                            style: const pw.TextStyle(fontSize: 8.5, color: _ink)),
                        pw.SizedBox(height: 6),
                      ],
                      pw.Text('Thank you for your business!',
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold, color: _brand)),
                      pw.SizedBox(height: 2),
                      pw.Text('This is a computer-generated invoice.',
                          style: const pw.TextStyle(fontSize: 8, color: _muted)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('For ${inv.businessName}',
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold, color: _ink)),
                  if (signature != null)
                    pw.Container(
                      width: 140,
                      height: 46,
                      margin: const pw.EdgeInsets.only(top: 4),
                      child: pw.Image(signature, fit: pw.BoxFit.contain),
                    )
                  else
                    pw.SizedBox(height: 26),
                  pw.Container(width: 140, height: 0.8, color: _muted),
                  pw.SizedBox(height: 3),
                  if ((inv.signatoryName ?? '').isNotEmpty)
                    pw.Text(inv.signatoryName!,
                        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _ink)),
                  pw.Text('Authorised signatory',
                      style: const pw.TextStyle(fontSize: 8, color: _muted)),
                ],
              ),
            ],
          ),
    ];

    const margin = pw.EdgeInsets.fromLTRB(30, 28, 30, 34);
    if (fitToContent) {
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat(PdfPageFormat.a4.width, double.infinity),
        margin: margin,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [...content, pw.SizedBox(height: 18), footerFor(1, 1)],
        ),
      ));
    } else {
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: margin,
        footer: (ctx) => footerFor(ctx.pageNumber, ctx.pagesCount),
        build: (ctx) => content,
      ));
    }

    return doc.save();
  }

  /// Renders the invoice as a PNG sized to its content - what WhatsApp shows inline
  /// as a picture in the chat, colours and all.
  static Future<List<Uint8List>> buildImages(Invoice inv, {double dpi = 170}) async {
    final pdf = await build(inv, fitToContent: true);
    final images = <Uint8List>[];
    await for (final page in Printing.raster(pdf, dpi: dpi)) {
      images.add(await page.toPng());
    }
    return images;
  }

  /// A short caption that goes with the image or PDF on WhatsApp.
  static String caption(Invoice inv) {
    final b = StringBuffer()
      ..writeln('*${inv.businessName}*')
      ..writeln('Invoice *${inv.invoiceNumber}* for ${inv.customerName}')
      ..writeln('Total: *${_rs(inv.grandTotal)}*');
    if (inv.balanceAmount > 0) {
      b.writeln('Balance due: *${_rs(inv.balanceAmount)}*');
    } else {
      b.writeln('Status: PAID - thank you!');
    }
    return b.toString().trim();
  }

  /// Shares the colour invoice as picture(s). The share sheet lists WhatsApp.
  static Future<void> shareImage(Invoice inv) async {
    final pngs = await buildImages(inv);
    await Share.shareXFiles(
      [
        for (var i = 0; i < pngs.length; i++)
          XFile.fromData(pngs[i],
              mimeType: 'image/png', name: imageName(inv, i + 1, pngs.length)),
      ],
      fileNameOverrides: [
        for (var i = 0; i < pngs.length; i++) imageName(inv, i + 1, pngs.length),
      ],
      text: caption(inv),
    );
  }

  /// Opens the system share sheet (WhatsApp, Gmail, Drive ...) with the PDF attached.
  static Future<void> share(Invoice inv) async =>
      Printing.sharePdf(bytes: await build(inv), filename: fileName(inv));

  /// Opens the system print dialog (Wi-Fi / Bluetooth printers, Save as PDF).
  static Future<void> printIt(Invoice inv) => Printing.layoutPdf(
        name: fileName(inv),
        onLayout: (_) => build(inv),
      );

  // ------------------------------------------------ 80 mm thermal receipt

  /// A till receipt for 80 mm thermal printers (supermarket / bar style).
  /// Black and white, compact, with a scan-to-pay QR when money is still due.
  static Future<Uint8List> buildReceipt(Invoice inv) async {
    final doc = pw.Document(title: 'Receipt ${inv.invoiceNumber}', creator: 'BizBill');
    final date = DateTime.tryParse(inv.invoiceDate)?.toLocal();
    final logoBytes = inv.showLogoOnReceipt ? await BrandingImages.load(inv.logoUrl) : null;
    final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
    const black = PdfColors.black;
    const grey = PdfColor.fromInt(0xFF444444);

    pw.Widget dashed() => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: pw.Container(
            height: 1,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(width: 0.8, style: pw.BorderStyle.dashed)),
            ),
          ),
        );
    pw.Widget center(String t, {double size = 8, bool bold = false, PdfColor color = black}) =>
        pw.Center(
          child: pw.Text(t,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  fontSize: size,
                  color: color,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );
    pw.Widget pair(String l, String v, {bool bold = false, double size = 8}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 0.8),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(l,
                  style: pw.TextStyle(
                      fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
              pw.Text(v,
                  style: pw.TextStyle(
                      fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
            ],
          ),
        );
    pw.Widget t(String s, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Text(s,
        textAlign: align,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal));

    final payLink = (inv.businessUpiId ?? '').isNotEmpty && inv.balanceAmount > 0 && !inv.isCancelled
        ? ShopUpi(
            businessId: inv.businessId,
            businessName: inv.businessName,
            upiId: inv.businessUpiId,
            upiName: inv.businessUpiName ?? inv.businessName,
          ).payLink(amount: inv.balanceAmount, note: 'Bill ${inv.invoiceNumber}')
        : null;
    final isWalkIn = inv.customerMobile == '0000000000';
    final totalQty = inv.items.fold<double>(0, (s, i) => s + i.quantity);

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.roll80.copyWith(
        marginLeft: 3 * PdfPageFormat.mm,
        marginRight: 3 * PdfPageFormat.mm,
        marginTop: 4 * PdfPageFormat.mm,
        marginBottom: 6 * PdfPageFormat.mm,
      ),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Center(
              child: pw.Container(
                height: 44,
                margin: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Image(logo, fit: pw.BoxFit.contain),
              ),
            ),
          center(inv.businessName.toUpperCase(), size: 12, bold: true),
          if ((inv.businessTagline ?? '').isNotEmpty) center(inv.businessTagline!, size: 7.5, color: grey),
          if ((inv.businessAddress ?? '').isNotEmpty) center(inv.businessAddress!, size: 7.5, color: grey),
          if (inv.businessMobile.isNotEmpty) center('Ph: ${inv.businessMobile}', size: 7.5, color: grey),
          if ((inv.businessGstNumber ?? '').isNotEmpty)
            center('GSTIN: ${inv.businessGstNumber}', size: 7.5, bold: true),
          pw.SizedBox(height: 3),
          center(inv.taxAmount > 0 ? 'TAX INVOICE' : 'CASH MEMO', size: 9, bold: true),
          dashed(),
          pair('Bill: ${inv.invoiceNumber}', date == null ? '' : _dateOnly.format(date)),
          pair(isWalkIn ? 'Customer: Walk-in' : 'Customer: ${inv.customerName}',
              date == null ? '' : _time.format(date)),
          if (!isWalkIn) pair('Mobile: ${inv.customerMobile}', ''),
          if ((inv.billedByName ?? '').isNotEmpty) pair('Cashier: ${inv.billedByName}', ''),
          dashed(),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(4.2),
              1: pw.FlexColumnWidth(1.3),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(2.3),
            },
            children: [
              pw.TableRow(children: [
                t('ITEM', bold: true),
                t('QTY', bold: true, align: pw.TextAlign.right),
                t('RATE', bold: true, align: pw.TextAlign.right),
                t('AMT', bold: true, align: pw.TextAlign.right),
              ]),
              for (final it in inv.items)
                pw.TableRow(
                  verticalAlignment: pw.TableCellVerticalAlignment.top,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: t(it.productName +
                          (it.taxPercent > 0 ? ' (${_qty(it.taxPercent)}%)' : '')),
                    ),
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: t(_qty(it.quantity), align: pw.TextAlign.right)),
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: t(_num.format(it.unitPrice), align: pw.TextAlign.right)),
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 2),
                        child: t(_num.format(it.lineTotal), align: pw.TextAlign.right)),
                  ],
                ),
            ],
          ),
          dashed(),
          pair('Items: ${inv.items.length}   Qty: ${_qty(totalQty)}', ''),
          pair('Sub total', _num.format(inv.subTotal)),
          if (inv.discountAmount > 0) pair('Discount', '-${_num.format(inv.discountAmount)}'),
          if (inv.taxAmount > 0) pair('GST', _num.format(inv.taxAmount)),
          dashed(),
          pair('TOTAL', 'Rs. ${_num.format(inv.grandTotal)}', bold: true, size: 11),
          dashed(),
          if (inv.tenders.isEmpty)
            pair('Paid (${inv.paymentMode == 'Credit' ? 'Udhaar' : inv.paymentMode})',
                _num.format(inv.paidAmount))
          else
            for (final t in inv.tenders)
              pair(
                  t.label +
                      ((t.cardApprovalCode ?? '').isNotEmpty ? ' auth ${t.cardApprovalCode}' : ''),
                  _num.format(t.amount)),
          if ((inv.changeReturned ?? 0) > 0) ...[
            pair('Cash given', _num.format(inv.cashTendered ?? 0)),
            pair('Change returned', _num.format(inv.changeReturned!)),
          ],
          if (inv.balanceAmount > 0) pair('BALANCE DUE', _num.format(inv.balanceAmount), bold: true),
          if ((inv.notes ?? '').isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(inv.notes!, style: const pw.TextStyle(fontSize: 7, color: grey)),
          ],
          if (payLink != null) ...[
            dashed(),
            center('SCAN TO PAY BY UPI', size: 8, bold: true),
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(), data: payLink, width: 90, height: 90),
            ),
            pw.SizedBox(height: 2),
            center(inv.businessUpiId!, size: 7.5),
          ],
          dashed(),
          center((inv.receiptFooter ?? '').isNotEmpty ? inv.receiptFooter! : 'Thank you! Visit again',
              size: 9, bold: true),
          center(amountInWords(inv.grandTotal), size: 6.5, color: grey),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: inv.invoiceNumber,
              width: 150,
              height: 26,
              drawText: false,
            ),
          ),
          center('Powered by BizBill', size: 6, color: grey),
        ],
      ),
    ));
    return doc.save();
  }

  /// Receipt printing. Windows prints straight to the chosen receipt printer
  /// (no dialog - like a till); phones use the system print sheet.
  static Future<void> printReceipt(Invoice inv, {Printer? printer}) async {
    if (printer != null) {
      await Printing.directPrintPdf(
        printer: printer,
        name: 'Receipt ${inv.invoiceNumber}',
        format: PdfPageFormat.roll80,
        onLayout: (_) => buildReceipt(inv),
      );
      return;
    }
    await Printing.layoutPdf(
      name: 'Receipt-${inv.invoiceNumber}',
      format: PdfPageFormat.roll80,
      onLayout: (_) => buildReceipt(inv),
    );
  }

  // --------------------------------------------------- amount in words
  static const _ones = [
    '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen',
    'Eighteen', 'Nineteen',
  ];
  static const _tens = [
    '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety',
  ];

  static String _below100(int n) =>
      n < 20 ? _ones[n] : '${_tens[n ~/ 10]}${n % 10 > 0 ? ' ${_ones[n % 10]}' : ''}';

  static String _below1000(int n) {
    final h = n ~/ 100, r = n % 100;
    return [
      if (h > 0) '${_ones[h]} Hundred',
      if (r > 0) _below100(r),
    ].join(' ');
  }

  /// Indian numbering: crore, lakh, thousand. 1234.5 ->
  /// "Rupees One Thousand Two Hundred Thirty Four and Fifty Paise Only".
  static String amountInWords(double amount) {
    final paiseTotal = (amount.abs() * 100).round();
    var rupees = paiseTotal ~/ 100;
    final paise = paiseTotal % 100;

    if (rupees == 0 && paise == 0) return 'Rupees Zero Only';

    final parts = <String>[];
    final crore = rupees ~/ 10000000;
    rupees %= 10000000;
    final lakh = rupees ~/ 100000;
    rupees %= 100000;
    final thousand = rupees ~/ 1000;
    rupees %= 1000;

    if (crore > 0) parts.add('${_below1000(crore % 1000)} Crore');
    if (lakh > 0) parts.add('${_below100(lakh)} Lakh');
    if (thousand > 0) parts.add('${_below100(thousand)} Thousand');
    if (rupees > 0) parts.add(_below1000(rupees));

    final words = parts.join(' ');
    final rupeePart = words.isEmpty ? '' : 'Rupees $words';
    final paisePart = paise > 0 ? '${_below100(paise)} Paise' : '';
    return [
      rupeePart,
      if (rupeePart.isNotEmpty && paisePart.isNotEmpty) 'and',
      paisePart,
      'Only',
    ].where((s) => s.isNotEmpty).join(' ');
  }
}

class _Col {
  const _Col(this.title, this.width, this.align);
  final String title;
  final pw.TableColumnWidth width;
  final pw.TextAlign align;
}
