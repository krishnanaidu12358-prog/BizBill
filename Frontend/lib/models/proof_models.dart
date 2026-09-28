// UPI payment proofs and running statements.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

class PaymentProof {
  PaymentProof({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.customerId,
    required this.customerName,
    required this.customerMobile,
    required this.amount,
    required this.method,
    required this.hasScreenshot,
    required this.status,
    required this.submittedAt,
    required this.invoiceBalance,
    required this.customerOutstanding,
    this.invoiceId,
    this.invoiceNumber,
    this.referenceNo,
    this.note,
    this.remarks,
    this.processedAt,
  });

  final int id;
  final int businessId;
  final String businessName;
  final int customerId;
  final String customerName;
  final String customerMobile;
  final double amount;
  final String method;
  final bool hasScreenshot;
  final String status;
  final String submittedAt;
  final double invoiceBalance;
  final double customerOutstanding;
  final int? invoiceId;
  final String? invoiceNumber;
  final String? referenceNo;
  final String? note;
  final String? remarks;
  final String? processedAt;

  bool get isPending => status == 'Pending';

  factory PaymentProof.fromJson(Map<String, dynamic> j) => PaymentProof(
        id: _i(j['id']),
        businessId: _i(j['businessId']),
        businessName: j['businessName'] ?? '',
        customerId: _i(j['customerId']),
        customerName: j['customerName'] ?? '',
        customerMobile: j['customerMobile'] ?? '',
        amount: _d(j['amount']),
        method: j['method'] ?? 'UPI',
        hasScreenshot: j['hasScreenshot'] == true,
        status: j['status'] ?? '',
        submittedAt: j['submittedAt'] ?? '',
        invoiceBalance: _d(j['invoiceBalance']),
        customerOutstanding: _d(j['customerOutstanding']),
        invoiceId: j['invoiceId'] == null ? null : _i(j['invoiceId']),
        invoiceNumber: j['invoiceNumber'],
        referenceNo: j['referenceNo'],
        note: j['note'],
        remarks: j['remarks'],
        processedAt: j['processedAt'],
      );
}

class StatementLine {
  StatementLine({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.grandTotal,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    required this.daysOld,
  });

  final int invoiceId;
  final String invoiceNumber;
  final String invoiceDate;
  final double grandTotal;
  final double paidAmount;
  final double balanceAmount;
  final String status;
  final int daysOld;

  factory StatementLine.fromJson(Map<String, dynamic> j) => StatementLine(
        invoiceId: _i(j['invoiceId']),
        invoiceNumber: j['invoiceNumber'] ?? '',
        invoiceDate: j['invoiceDate'] ?? '',
        grandTotal: _d(j['grandTotal']),
        paidAmount: _d(j['paidAmount']),
        balanceAmount: _d(j['balanceAmount']),
        status: j['status'] ?? '',
        daysOld: _i(j['daysOld']),
      );
}

class Statement {
  Statement({
    required this.customerId,
    required this.customerName,
    required this.customerMobile,
    required this.businessId,
    required this.businessName,
    required this.unpaidBills,
    required this.totalBilled,
    required this.totalPaid,
    required this.totalDue,
    required this.creditAvailable,
    required this.oldestBillDays,
  });

  final int customerId;
  final String customerName;
  final String customerMobile;
  final int businessId;
  final String businessName;
  final List<StatementLine> unpaidBills;
  final double totalBilled;
  final double totalPaid;
  final double totalDue;
  final double creditAvailable;
  final int oldestBillDays;

  factory Statement.fromJson(Map<String, dynamic> j) => Statement(
        customerId: _i(j['customerId']),
        customerName: j['customerName'] ?? '',
        customerMobile: j['customerMobile'] ?? '',
        businessId: _i(j['businessId']),
        businessName: j['businessName'] ?? '',
        totalBilled: _d(j['totalBilled']),
        totalPaid: _d(j['totalPaid']),
        totalDue: _d(j['totalDue']),
        creditAvailable: _d(j['creditAvailable']),
        oldestBillDays: _i(j['oldestBillDays']),
        unpaidBills: ((j['unpaidBills'] as List?) ?? [])
            .map((e) => StatementLine.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ProofApprovalResult {
  ProofApprovalResult({
    required this.remainingOnInvoice,
    required this.customerOutstanding,
    this.whatsAppLink,
  });

  final double remainingOnInvoice;
  final double customerOutstanding;
  final String? whatsAppLink;

  factory ProofApprovalResult.fromJson(Map<String, dynamic> j) => ProofApprovalResult(
        remainingOnInvoice: _d(j['remainingOnInvoice']),
        customerOutstanding: _d(j['customerOutstanding']),
        whatsAppLink: j['whatsAppLink'],
      );
}

/// A shop's UPI details. The customer pays straight into this account.
class ShopUpi {
  ShopUpi({
    required this.businessId,
    required this.businessName,
    required this.upiName,
    this.upiId,
    this.outstanding,
  });

  final int businessId;
  final String businessName;
  final String? upiId;
  final String upiName;
  final double? outstanding;

  bool get isSetUp => (upiId ?? '').isNotEmpty;

  factory ShopUpi.fromJson(Map<String, dynamic> j) => ShopUpi(
        businessId: _i(j['businessId']),
        businessName: j['businessName'] ?? '',
        upiId: j['upiId'],
        upiName: j['upiName'] ?? j['businessName'] ?? '',
        outstanding: j['outstanding'] == null ? null : _d(j['outstanding']),
      );

  /// Standard UPI payment link (NPCI format). Any UPI app - Google Pay, PhonePe,
  /// Paytm, BHIM, bank apps - opens it, and the same text is what the QR holds.
  /// Leave [amount] null for an open-amount QR the payer fills in.
  String payLink({double? amount, String? note}) {
    final params = <String, String>{
      'pa': upiId ?? '',
      'pn': upiName,
      if (amount != null && amount > 0) 'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      if (note != null && note.isNotEmpty) 'tn': note.length > 50 ? note.substring(0, 50) : note,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'upi://pay?$query';
  }
}
