// Models for the customer-reputation lookup and the
// Super Admin drill-down screens. Shared shapes come from models.dart.

import 'models.dart';

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

// --------------------------- lookup ------------------------------------

class CustomerInsight {
  CustomerInsight({
    required this.found,
    required this.mobile,
    required this.name,
    required this.hasAppAccount,
    required this.ratingLabel,
    required this.shopCount,
    required this.totalBills,
    required this.paymentSignal,
    required this.hasOverdueElsewhere,
    required this.summary,
    this.rating,
    this.memberSince,
    this.thisShop,
  });

  final bool found;
  final String mobile;
  final String name;
  final bool hasAppAccount;
  final String ratingLabel;
  final int shopCount;
  final int totalBills;
  final String paymentSignal;
  final bool hasOverdueElsewhere;
  final String summary;
  final double? rating;
  final String? memberSince;
  final InsightLocal? thisShop;

  factory CustomerInsight.fromJson(Map<String, dynamic> j) => CustomerInsight(
        found: j['found'] == true,
        mobile: j['mobile'] ?? '',
        name: j['name'] ?? '',
        hasAppAccount: j['hasAppAccount'] == true,
        ratingLabel: j['ratingLabel'] ?? '',
        shopCount: _i(j['shopCount']),
        totalBills: _i(j['totalBills']),
        paymentSignal: j['paymentSignal'] ?? '',
        hasOverdueElsewhere: j['hasOverdueElsewhere'] == true,
        summary: j['summary'] ?? '',
        rating: j['rating'] == null ? null : _d(j['rating']),
        memberSince: j['memberSince'],
        thisShop: j['thisShop'] == null
            ? null
            : InsightLocal.fromJson(j['thisShop'] as Map<String, dynamic>),
      );
}

class InsightLocal {
  InsightLocal({
    required this.customerId,
    required this.name,
    required this.isTrusted,
    required this.creditLimit,
    required this.outstandingBalance,
    required this.creditBalance,
    required this.billCount,
    this.lastBillOn,
  });

  final int customerId;
  final String name;
  final bool isTrusted;
  final double creditLimit;
  final double outstandingBalance;
  final double creditBalance;
  final int billCount;
  final String? lastBillOn;

  factory InsightLocal.fromJson(Map<String, dynamic> j) => InsightLocal(
        customerId: _i(j['customerId']),
        name: j['name'] ?? '',
        isTrusted: j['isTrusted'] == true,
        creditLimit: _d(j['creditLimit']),
        outstandingBalance: _d(j['outstandingBalance']),
        creditBalance: _d(j['creditBalance']),
        billCount: _i(j['billCount']),
        lastBillOn: j['lastBillOn'],
      );
}

// --------------------------- payments ----------------------------------

class PaymentRow {
  PaymentRow({
    required this.id,
    required this.receiptNumber,
    required this.partyName,
    required this.amount,
    required this.mode,
    required this.paidOn,
    this.invoiceId,
    this.referenceNo,
  });

  final int id;
  final String receiptNumber;

  /// Shop name when a customer is looking, customer name when a shop is.
  final String partyName;
  final double amount;
  final String mode;
  final String paidOn;
  final int? invoiceId;
  final String? referenceNo;

  factory PaymentRow.fromJson(Map<String, dynamic> j) => PaymentRow(
        id: _i(j['id']),
        receiptNumber: j['receiptNumber'] ?? '',
        partyName: j['customerName'] ?? '',
        amount: _d(j['amount']),
        mode: j['mode'] ?? '',
        paidOn: j['paidOn'] ?? '',
        invoiceId: j['invoiceId'] == null ? null : _i(j['invoiceId']),
        referenceNo: j['referenceNo'],
      );
}

// ------------------------ admin drill-downs ----------------------------

class AdminBusinessProfile {
  AdminBusinessProfile({
    required this.id,
    required this.name,
    required this.mobile,
    required this.invoicePrefix,
    required this.isActive,
    required this.createdAt,
    required this.fullAddress,
    this.ownerName,
    this.email,
    this.city,
    this.state,
    this.pincode,
    this.gstNumber,
  });

  final int id;
  final String name;
  final String mobile;
  final String invoicePrefix;
  final bool isActive;
  final String createdAt;
  final String fullAddress;
  final String? ownerName;
  final String? email;
  final String? city;
  final String? state;
  final String? pincode;
  final String? gstNumber;

  factory AdminBusinessProfile.fromJson(Map<String, dynamic> j) => AdminBusinessProfile(
        id: _i(j['id']),
        name: j['name'] ?? '',
        mobile: j['mobile'] ?? '',
        invoicePrefix: j['invoicePrefix'] ?? '',
        isActive: j['isActive'] == true,
        createdAt: j['createdAt'] ?? '',
        fullAddress: j['fullAddress'] ?? '',
        ownerName: j['ownerName'],
        email: j['email'],
        city: j['city'],
        state: j['state'],
        pincode: j['pincode'],
        gstNumber: j['gstNumber'],
      );
}

class AdminBusinessStats {
  AdminBusinessStats({
    required this.customerCount,
    required this.trustedCustomerCount,
    required this.productCount,
    required this.lowStockCount,
    required this.invoiceCount,
    required this.totalSales,
    required this.totalCollected,
    required this.receivable,
    required this.creditIssued,
    required this.creditUnclaimed,
    required this.pendingClaimCount,
    required this.whatsAppSent,
    this.lastInvoiceOn,
    this.totalExpenses = 0,
    this.totalDiscount = 0,
    this.totalTax = 0,
    this.netAfterExpenses = 0,
  });

  final int customerCount;
  final int trustedCustomerCount;
  final int productCount;
  final int lowStockCount;
  final int invoiceCount;
  final double totalSales;
  final double totalCollected;
  final double receivable;
  final double creditIssued;
  final double creditUnclaimed;
  final int pendingClaimCount;
  final int whatsAppSent;
  final String? lastInvoiceOn;
  final double totalExpenses;
  final double totalDiscount;
  final double totalTax;
  final double netAfterExpenses;

  factory AdminBusinessStats.fromJson(Map<String, dynamic> j) => AdminBusinessStats(
        customerCount: _i(j['customerCount']),
        trustedCustomerCount: _i(j['trustedCustomerCount']),
        productCount: _i(j['productCount']),
        lowStockCount: _i(j['lowStockCount']),
        invoiceCount: _i(j['invoiceCount']),
        totalSales: _d(j['totalSales']),
        totalCollected: _d(j['totalCollected']),
        receivable: _d(j['receivable']),
        creditIssued: _d(j['creditIssued']),
        creditUnclaimed: _d(j['creditUnclaimed']),
        pendingClaimCount: _i(j['pendingClaimCount']),
        whatsAppSent: _i(j['whatsAppSent']),
        lastInvoiceOn: j['lastInvoiceOn'],
        totalExpenses: _d(j['totalExpenses']),
        totalDiscount: _d(j['totalDiscount']),
        totalTax: _d(j['totalTax']),
        netAfterExpenses: _d(j['netAfterExpenses']),
      );
}

class AdminUserDetail {
  AdminUserDetail({
    required this.account,
    required this.stats,
    required this.customers,
    this.business,
  });

  final AdminUser account;
  final AdminBusinessStats stats;
  final List<Customer> customers;
  final AdminBusinessProfile? business;

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) => AdminUserDetail(
        account: AdminUser.fromJson(j['account'] as Map<String, dynamic>),
        business: j['business'] == null
            ? null
            : AdminBusinessProfile.fromJson(j['business'] as Map<String, dynamic>),
        stats: AdminBusinessStats.fromJson(
            (j['stats'] as Map<String, dynamic>?) ?? <String, dynamic>{}),
        customers: ((j['customers'] as List?) ?? [])
            .map((e) => Customer.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AdminCustomerDetail {
  AdminCustomerDetail({
    required this.customer,
    required this.businessName,
    required this.businessMobile,
    required this.insight,
    required this.otherShops,
    required this.bills,
    required this.payments,
    required this.credits,
    required this.claims,
    required this.ledger,
    required this.messages,
    this.account,
  });

  final Customer customer;
  final String businessName;
  final String businessMobile;
  final CustomerInsight insight;
  final List<ShopSummary> otherShops;
  final List<Invoice> bills;
  final List<PaymentRow> payments;
  final List<CreditGrant> credits;
  final List<CreditClaim> claims;
  final List<LedgerRow> ledger;
  final List<WhatsAppLogRow> messages;
  final AdminUser? account;

  factory AdminCustomerDetail.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) make) =>
        ((j[key] as List?) ?? []).map((e) => make(e as Map<String, dynamic>)).toList();

    return AdminCustomerDetail(
      customer: Customer.fromJson(j['customer'] as Map<String, dynamic>),
      businessName: j['businessName'] ?? '',
      businessMobile: j['businessMobile'] ?? '',
      account: j['account'] == null
          ? null
          : AdminUser.fromJson(j['account'] as Map<String, dynamic>),
      insight: CustomerInsight.fromJson(
          (j['insight'] as Map<String, dynamic>?) ?? <String, dynamic>{}),
      otherShops: list('otherShops', ShopSummary.fromJson),
      bills: list('bills', Invoice.fromJson),
      payments: list('payments', PaymentRow.fromJson),
      credits: list('credits', CreditGrant.fromJson),
      claims: list('claims', CreditClaim.fromJson),
      ledger: list('ledger', LedgerRow.fromJson),
      messages: list('messages', WhatsAppLogRow.fromJson),
    );
  }
}
