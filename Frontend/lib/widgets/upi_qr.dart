import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../models/proof_models.dart';
import 'common.dart';

/// The shop's UPI QR with its name and UPI ID underneath. Any UPI app can scan
/// it; when [amount] is set the amount is filled in for the payer.
class UpiQrCard extends StatelessWidget {
  const UpiQrCard({
    super.key,
    required this.upi,
    this.amount,
    this.note,
    this.size = 210,
  });

  final ShopUpi upi;
  final double? amount;
  final String? note;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final link = upi.payLink(amount: amount, note: note);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.qr_code_2, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Text('Scan & pay with any UPI app',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 12),
            // QR codes must be dark-on-light to scan, even in dark mode.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.35), width: 2),
              ),
              child: QrImageView(
                data: link,
                version: QrVersions.auto,
                size: size,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0F5C43)),
                dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111827)),
              ),
            ),
            const SizedBox(height: 12),
            Text(upi.upiName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => copyUpiId(context, upi.upiId!),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(upi.upiId ?? '',
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
                    const SizedBox(width: 6),
                    Icon(Icons.copy, size: 15, color: scheme.primary),
                  ],
                ),
              ),
            ),
            if (amount != null && amount! > 0) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('Amount ${money(amount)}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> copyUpiId(BuildContext context, String upiId) async {
  await Clipboard.setData(ClipboardData(text: upiId));
  if (context.mounted) showSnack(context, 'UPI ID copied: $upiId');
}

/// Draws the QR on a white card with the payee name, as a PNG to share or save.
/// A customer paying from the same phone can open it in their UPI app with
/// "Scan from gallery".
Future<Uint8List> upiQrPng(ShopUpi upi, {double? amount, String? note}) async {
  const qrSize = 720.0;
  const pad = 60.0;
  const textArea = 170.0;
  const width = qrSize + pad * 2;
  const height = qrSize + pad * 2 + textArea;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), Paint()..color = Colors.white);

  final painter = QrPainter(
    data: upi.payLink(amount: amount, note: note),
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF0F5C43)),
    dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square, color: Color(0xFF111827)),
  );
  canvas.save();
  canvas.translate(pad, pad);
  painter.paint(canvas, const Size(qrSize, qrSize));
  canvas.restore();

  void text(String t, double y, double fontSize, FontWeight weight, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: t, style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color)),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: width - pad);
    tp.paint(canvas, Offset((width - tp.width) / 2, y));
  }

  text(upi.upiName, qrSize + pad + 20, 44, FontWeight.bold, const Color(0xFF111827));
  text(upi.upiId ?? '', qrSize + pad + 78, 32, FontWeight.normal, const Color(0xFF4B5563));
  if (amount != null && amount > 0) {
    text('Amount ${money(amount)}', qrSize + pad + 120, 32, FontWeight.bold,
        const Color(0xFF0F5C43));
  }

  final image = await recorder.endRecording().toImage(width.toInt(), height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> shareUpiQr(BuildContext context, ShopUpi upi, {double? amount, String? note}) async {
  try {
    final png = await upiQrPng(upi, amount: amount, note: note);
    final name = 'UPI-QR-${upi.upiName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_')}.png';
    await Share.shareXFiles(
      [XFile.fromData(png, mimeType: 'image/png', name: name)],
      fileNameOverrides: [name],
      text: 'Pay ${upi.upiName} by UPI: ${upi.upiId}'
          '${amount != null && amount > 0 ? ' - ${money(amount)}' : ''}',
    );
  } catch (e) {
    if (context.mounted) showSnack(context, 'Could not share the QR: $e', error: true);
  }
}
