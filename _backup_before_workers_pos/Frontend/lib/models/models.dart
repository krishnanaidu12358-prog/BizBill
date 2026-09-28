// Plain data holders mapped from the API's JSON.

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

class UserProfile {
  UserProfile({
    required this.id,
    required this.mobile,
    required this.fullName,
    required this.role,
    this.email,
    this.businessId,
    this.businessName,
    this.themeMode = 'System',
    this.themeName = 'Classic',
  });

  final int id;
  final String mobile;
  final String fullName;
  final String role;
  final String? email;
  final int? businessId;
  final String? businessName;
  final String themeMode;
  final String themeName;

  bool get isAdmin => role == 'SuperAdmin';
  bool get isOwner => role == 'BusinessUser';
  bool get isCustomer => role == 'Customer';

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        id: _i(j['id']),
        mobile: j['mobile'] ?? '',
        fullName: j['fullName'] ?? '',
        role: j['role'] ?? '',
        email: j['email'],
        businessId: j['businessId'] == null ? null : _i(j['businessId']),
        businessName: j['businessName'],
        themeMode: j['themeMode'] ?? 'System',
        themeName: j['themeName'] ?? 'Classic',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'mobile': mobile,
        'fullName': fullName,
        'role': role,
        'email': email,
        'businessId': businessId,
        'businessName': businessName,
        'themeMode': themeMode,
        'themeName': themeName,
      };
}

class Customer {
  Customer({
    required this.id,
    required this.businessId,
    required this.name,
    required this.mobile,
    required this.isTrusted,
    required this.creditLimit,
    required this.outstandingBalance,
    required this.creditBalance,
    required this.hasAppAccount,
    this.address,
    this.email,
  });

  final int id;
  final int businessId;
  final String name;
  final String mobile;
  final bool isTrusted;
  final double creditLimit;
  final double outstandingBalance;
  final double creditBalance;
  final bool hasAppAccount;
  final String? address;
  final String? email;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: _i(j['id']),
        businessId: _i(j['businessId']),
        name: j['name'] ?? '',
        mobile: j['mobile'] ?? '',
        isTrusted: j['isTrusted'] == true,
        creditLimit: _d(j['creditLimit']),
        outstandingBalance: _d(j['outstandingBalance']),
        creditBalance: _d(j['creditBalance']),
        hasAppAccount: j['hasAppAccount'] == true,
        address: j['address'],
        email: j['email'],
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.unit,
    required this.sellingPrice,
    required this.taxPercent,
    required this.stockQty,
    required this.minStockQty,
    required this.isLowStock,
    this.sku,
    this.barcode,
  });

  final int id;
  final String name;
  final String unit;
  final double sellingPrice;
  final double taxPercent;
  final double stockQty;
  final double minStockQty;
  final bool isLowStock;
  final String? sku;
  final String? barcode;

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: _i(j['id']),
        name: j['name'] ?? '',
        unit: j['unit'] ?? 'PCS',
        sellingPrice: _d(j['sellingPrice']),
        taxPercent: _d(j['taxPercent']),
        stockQty: _d(j['stockQty']),
        minStockQty: _d(j['minStockQty']),
        isLowStock: j['isLowStock'] == true,
        sku: j['sku'],
        barcode: j['barcode'],
      );
}

class InvoiceItem {
  InvoiceItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.taxPercent,
    required this.lineTotal,
    this.taxAmount = 0,
    this.discountAmount = 0,
  });

  final String productName;
  final double quantity;
  final double unitPrice;
  final double taxPercent;
  final double lineTotal;
  final double taxAmount;
  final double discountAmount;

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        productName: j['productName'] ?? '',
        quantity: _d(j['quantity']),
        unitPrice: _d(j['unitPrice']),
        taxPercent: _d(j['taxPercent']),
        lineTotal: _d(j['lineTotal']),
        taxAmount: _d(j['taxAmount']),
        discountAmount: _d(j['discountAmount']),
      );
}

class Invoice {
  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.businessName,
    required this.customerId,
    required this.customerName,
    required this.customerMobile,
    required this.subTotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.grandTotal,
    required this.paidAmount,
    required this.balanceAmount,
    required this.paymentMode,
    required this.status,
    required this.items,
    this.notes,
    this.whatsAppLink,
    this.businessId = 0,
    this.businessMobile = '',
    this.businessAddress,
    this.businessGstNumber,
    this.businessUpiId,
    this.businessUpiName,
    this.customerAddress,
    this.customerOutstanding = 0,
  });

  final int id;
  final String invoiceNumber;
  final String invoiceDate;
  final String businessName;
  final int customerId;
  final String customerName;
  final String customerMobile;
  final double subTotal;
  final double discountAmount;
  final double taxAmount;
  final double grandTotal;
  final double paidAmount;
  final double balanceAmount;
  final String paymentMode;
  final String status;
  final List<InvoiceItem> items;
  final String? notes;
  final String? whatsAppLink;
  final int businessId;
  final String businessMobile;
  final String? businessAddress;
  final String? businessGstNumber;
  final String? businessUpiId;
  final String? businessUpiName;
  final String? customerAddress;

  /// Everything the customer owes this shop, this bill included.
  final double customerOutstanding;

  bool get isCancelled => status == 'Cancelled';

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: _i(j['id']),
        invoiceNumber: j['invoiceNumber'] ?? '',
        invoiceDate: j['invoiceDate'] ?? '',
        businessName: j['businessName'] ?? '',
        customerId: _i(j['customerId']),
        customerName: j['customerName'] ?? '',
        customerMobile: j['customerMobile'] ?? '',
        subTotal: _d(j['subTotal']),
        discountAmount: _d(j['discountAmount']),
        taxAmount: _d(j['taxAmount']),
        grandTotal: _d(j['grandTotal']),
        paidAmount: _d(j['paidAmount']),
        balanceAmount: _d(j['balanceAmount']),
        paymentMode: j['paymentMode'] ?? '',
        status: j['status'] ?? '',
        notes: j['notes'],
        whatsAppLink: j['whatsAppLink'],
        businessId: _i(j['businessId']),
        businessMobile: j['businessMobile'] ?? '',
        businessAddress: j['businessAddress'],
        businessGstNumber: j['businessGstNumber'],
        businessUpiId: j['businessUpiId'],
        businessUpiName: j['businessUpiName'],
        customerAddress: j['customerAddress'],
        customerOutstanding: _d(j['customerOutstanding']),
        items: ((j['items'] as List?) ?? [])
            .map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class CreditGrant {
  CreditGrant({
    required this.id,
    required this.creditCode,
    required this.businessId,
    required this.businessName,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.claimedAmount,
    required this.balanceAmount,
    required this.status,
    required this.createdAt,
    this.reason,
    this.expiryDate,
    this.whatsAppLink,
  });

  final int id;
  final String creditCode;
  final int businessId;
  final String businessName;
  final int customerId;
  final String customerName;
  final double amount;
  final double claimedAmount;
  final double balanceAmount;
  final String status;
  final String createdAt;
  final String? reason;
  final String? expiryDate;
  final String? whatsAppLink;

  bool get isClaimable =>
      balanceAmount > 0 && (status == 'Active' || status == 'PartiallyClaimed');

  factory CreditGrant.fromJson(Map<String, dynamic> j) => CreditGrant(
        id: _i(j['id']),
        creditCode: j['creditCode'] ?? '',
        businessId: _i(j['businessId']),
        businessName: j['businessName'] ?? '',
        customerId: _i(j['customerId']),
        customerName: j['customerName'] ?? '',
        amount: _d(j['amount']),
        claimedAmount: _d(j['claimedAmount']),
        balanceAmount: _d(j['balanceAmount']),
        status: j['status'] ?? '',
        createdAt: j['createdAt'] ?? '',
        reason: j['reason'],
        expiryDate: j['expiryDate'],
        whatsAppLink: j['whatsAppLink'],
      );
}

class CreditClaim {
  CreditClaim({
    required this.id,
    required this.creditGrantId,
    required this.creditCode,
    required this.businessName,
    required this.customerName,
    required this.customerMobile,
    required this.amount,
    required this.status,
    required this.requestedAt,
    this.remarks,
  });

  final int id;
  final int creditGrantId;
  final String creditCode;
  final String businessName;
  final String customerName;
  final String customerMobile;
  final double amount;
  final String status;
  final String requestedAt;
  final String? remarks;

  factory CreditClaim.fromJson(Map<String, dynamic> j) => CreditClaim(
        id: _i(j['id']),
        creditGrantId: _i(j['creditGrantId']),
        creditCode: j['creditCode'] ?? '',
        businessName: j['businessName'] ?? '',
        customerName: j['customerName'] ?? '',
        customerMobile: j['customerMobile'] ?? '',
        amount: _d(j['amount']),
        status: j['status'] ?? '',
        requestedAt: j['requestedAt'] ?? '',
        remarks: j['remarks'],
      );
}

class LedgerRow {
  LedgerRow({
    required this.entryDate,
    required this.refType,
    required this.description,
    required this.debit,
    required this.credit,
    required this.runningBalance,
  });

  final String entryDate;
  final String refType;
  final String description;
  final double debit;
  final double credit;
  final double runningBalance;

  factory LedgerRow.fromJson(Map<String, dynamic> j) => LedgerRow(
        entryDate: j['entryDate'] ?? '',
        refType: j['refType'] ?? '',
        description: j['description'] ?? '',
        debit: _d(j['debit']),
        credit: _d(j['credit']),
        runningBalance: _d(j['runningBalance']),
      );
}

class OwnerDashboard {
  OwnerDashboard({
    required this.businessName,
    required this.todaySales,
    required this.monthSales,
    required this.totalReceivable,
    required this.todayCollection,
    required this.outstandingCreditIssued,
    required this.customerCount,
    required this.productCount,
    required this.lowStockCount,
    required this.pendingClaimCount,
    required this.invoiceCountThisMonth,
    required this.recentInvoices,
    this.monthExpenses = 0,
  });

  final String businessName;
  final double todaySales;
  final double monthSales;
  final double totalReceivable;
  final double todayCollection;
  final double outstandingCreditIssued;
  final int customerCount;
  final int productCount;
  final int lowStockCount;
  final int pendingClaimCount;
  final int invoiceCountThisMonth;
  final List<Invoice> recentInvoices;
  final double monthExpenses;

  factory OwnerDashboard.fromJson(Map<String, dynamic> j) => OwnerDashboard(
        businessName: j['businessName'] ?? '',
        todaySales: _d(j['todaySales']),
        monthSales: _d(j['monthSales']),
        totalReceivable: _d(j['totalReceivable']),
        todayCollection: _d(j['todayCollection']),
        outstandingCreditIssued: _d(j['outstandingCreditIssued']),
        customerCount: _i(j['customerCount']),
        productCount: _i(j['productCount']),
        lowStockCount: _i(j['lowStockCount']),
        pendingClaimCount: _i(j['pendingClaimCount']),
        invoiceCountThisMonth: _i(j['invoiceCountThisMonth']),
        monthExpenses: _d(j['monthExpenses']),
        recentInvoices: ((j['recentInvoices'] as List?) ?? [])
            .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class ShopSummary {
  ShopSummary({
    required this.customerId,
    required this.businessId,
    required this.businessName,
    required this.businessMobile,
    required this.outstanding,
    required this.creditAvailable,
    required this.isTrusted,
  });

  final int customerId;
  final int businessId;
  final String businessName;
  final String businessMobile;
  final double outstanding;
  final double creditAvailable;
  final bool isTrusted;

  factory ShopSummary.fromJson(Map<String, dynamic> j) => ShopSummary(
        customerId: _i(j['customerId']),
        businessId: _i(j['businessId']),
        businessName: j['businessName'] ?? '',
        businessMobile: j['businessMobile'] ?? '',
        outstanding: _d(j['outstanding']),
        creditAvailable: _d(j['creditAvailable']),
        isTrusted: j['isTrusted'] == true,
      );
}

class CustomerDashboard {
  CustomerDashboard({
    required this.fullName,
    required this.mobile,
    required this.totalOutstanding,
    required this.totalCreditAvailable,
    required this.billCount,
    required this.shopCount,
    required this.shops,
  });

  final String fullName;
  final String mobile;
  final double totalOutstanding;
  final double totalCreditAvailable;
  final int billCount;
  final int shopCount;
  final List<ShopSummary> shops;

  factory CustomerDashboard.fromJson(Map<String, dynamic> j) => CustomerDashboard(
        fullName: j['fullName'] ?? '',
        mobile: j['mobile'] ?? '',
        totalOutstanding: _d(j['totalOutstanding']),
        totalCreditAvailable: _d(j['totalCreditAvailable']),
        billCount: _i(j['billCount']),
        shopCount: _i(j['shopCount']),
        shops: ((j['shops'] as List?) ?? [])
            .map((e) => ShopSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AdminDashboard {
  AdminDashboard({
    required this.businessCount,
    required this.activeBusinessCount,
    required this.businessUserCount,
    required this.customerUserCount,
    required this.invoiceCount,
    required this.totalSales,
    required this.totalReceivable,
    required this.totalCreditIssued,
    required this.totalCreditUnclaimed,
    required this.whatsAppSent,
    required this.whatsAppFailed,
  });

  final int businessCount;
  final int activeBusinessCount;
  final int businessUserCount;
  final int customerUserCount;
  final int invoiceCount;
  final double totalSales;
  final double totalReceivable;
  final double totalCreditIssued;
  final double totalCreditUnclaimed;
  final int whatsAppSent;
  final int whatsAppFailed;

  factory AdminDashboard.fromJson(Map<String, dynamic> j) => AdminDashboard(
        businessCount: _i(j['businessCount']),
        activeBusinessCount: _i(j['activeBusinessCount']),
        businessUserCount: _i(j['businessUserCount']),
        customerUserCount: _i(j['customerUserCount']),
        invoiceCount: _i(j['invoiceCount']),
        totalSales: _d(j['totalSales']),
        totalReceivable: _d(j['totalReceivable']),
        totalCreditIssued: _d(j['totalCreditIssued']),
        totalCreditUnclaimed: _d(j['totalCreditUnclaimed']),
        whatsAppSent: _i(j['whatsAppSent']),
        whatsAppFailed: _i(j['whatsAppFailed']),
      );
}

class AdminBusiness {
  AdminBusiness({
    required this.id,
    required this.name,
    required this.mobile,
    required this.isActive,
    required this.customerCount,
    required this.invoiceCount,
    required this.totalSales,
    required this.receivable,
    required this.ownerUserId,
    this.ownerName,
    this.city,
  });

  final int id;
  final String name;
  final String mobile;
  final bool isActive;
  final int customerCount;
  final int invoiceCount;
  final double totalSales;
  final double receivable;
  final int ownerUserId;
  final String? ownerName;
  final String? city;

  factory AdminBusiness.fromJson(Map<String, dynamic> j) => AdminBusiness(
        id: _i(j['id']),
        name: j['name'] ?? '',
        mobile: j['mobile'] ?? '',
        isActive: j['isActive'] == true,
        customerCount: _i(j['customerCount']),
        invoiceCount: _i(j['invoiceCount']),
        totalSales: _d(j['totalSales']),
        receivable: _d(j['receivable']),
        ownerUserId: _i(j['ownerUserId']),
        ownerName: j['ownerName'],
        city: j['city'],
      );
}

class AdminUser {
  AdminUser({
    required this.id,
    required this.mobile,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.businessName,
    this.lastLoginAt,
  });

  final int id;
  final String mobile;
  final String fullName;
  final String role;
  final bool isActive;
  final String? businessName;
  final String? lastLoginAt;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: _i(j['id']),
        mobile: j['mobile'] ?? '',
        fullName: j['fullName'] ?? '',
        role: j['role'] ?? '',
        isActive: j['isActive'] == true,
        businessName: j['businessName'],
        lastLoginAt: j['lastLoginAt'],
      );
}

class WhatsAppLogRow {
  WhatsAppLogRow({
    required this.id,
    required this.toMobile,
    required this.template,
    required this.body,
    required this.status,
    required this.createdAt,
    this.businessName,
    this.deepLink,
    this.errorMessage,
  });

  final int id;
  final String toMobile;
  final String template;
  final String body;
  final String status;
  final String createdAt;
  final String? businessName;
  final String? deepLink;
  final String? errorMessage;

  factory WhatsAppLogRow.fromJson(Map<String, dynamic> j) => WhatsAppLogRow(
        id: _i(j['id']),
        toMobile: j['toMobile'] ?? '',
        template: j['template'] ?? '',
        body: j['body'] ?? '',
        status: j['status'] ?? '',
        createdAt: j['createdAt'] ?? '',
        businessName: j['businessName'],
        deepLink: j['deepLink'],
        errorMessage: j['errorMessage'],
      );
}
