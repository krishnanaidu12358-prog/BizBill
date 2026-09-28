import 'package:bizflow_app/models/models.dart';
import 'package:bizflow_app/services/invoice_pdf.dart';
import 'package:bizflow_app/widgets/charts.dart';
import 'package:flutter_test/flutter_test.dart';

Invoice _invoice({double tax = 43.2, double balance = 403.2, String status = 'Credit'}) =>
    Invoice.fromJson({
      'id': 8,
      'invoiceNumber': 'SLE-001-00005',
      'invoiceDate': '2026-09-21T12:17:27Z',
      'businessName': 'Sri Lakshmi Electricals',
      'businessMobile': '9999911111',
      'businessAddress': '12-3-45, Main Bazaar Road, Hyderabad',
      'businessGstNumber': '36ABCDE1234F1Z5',
      'customerId': 1,
      'customerName': 'Ramesh Kumar',
      'customerMobile': '9876500001',
      'customerOutstanding': 1055.6,
      'subTotal': 360,
      'discountAmount': 0,
      'taxAmount': tax,
      'grandTotal': 360 + tax,
      'paidAmount': 360 + tax - balance,
      'balanceAmount': balance,
      'paymentMode': 'Credit',
      'status': status,
      'notes': 'Deliver by evening',
      'items': [
        {
          'productName': 'LED Bulb 9W',
          'quantity': 3,
          'unitPrice': 120,
          'taxPercent': tax > 0 ? 12 : 0,
          'taxAmount': tax,
          'lineTotal': 360 + tax,
        },
      ],
    });

void main() {
  test('builds a GST invoice PDF', () async {
    final bytes = await InvoicePdf.build(_invoice());
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });

  test('builds a paid, non-GST invoice (different column layout)', () async {
    final bytes = await InvoicePdf.build(_invoice(tax: 0, balance: 0, status: 'Paid'));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('amount in words uses Indian numbering', () {
    expect(InvoicePdf.amountInWords(403.2),
        'Rupees Four Hundred Three and Twenty Paise Only');
    expect(InvoicePdf.amountInWords(1250000),
        'Rupees Twelve Lakh Fifty Thousand Only');
    expect(InvoicePdf.amountInWords(0), 'Rupees Zero Only');
  });

  test('file name is safe for share sheets', () {
    expect(InvoicePdf.fileName(_invoice()), 'Invoice-SLE-001-00005.pdf');
  });

  test('compact rupees use K / L / Cr', () {
    expect(compactRs(950), '₹950');
    expect(compactRs(12500), '₹12.5K');
    expect(compactRs(320000), '₹3.2L');
    expect(compactRs(11000000), '₹1.1Cr');
    expect(compactRs(-4209.55), '-₹4.2K');
  });
}
