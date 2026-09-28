import 'dart:typed_data';

import '../core/api_client.dart';
import '../models/admin_models.dart';
import '../models/analytics_models.dart';
import '../models/models.dart';
import '../models/proof_models.dart';

/// Typed wrapper over the API. One place where endpoints are named.
class Repo {
  Repo(this.api);

  final ApiClient api;

  static List<Map<String, dynamic>> _items(dynamic data) {
    if (data is Map<String, dynamic> && data['items'] is List) {
      return (data['items'] as List).cast<Map<String, dynamic>>();
    }
    if (data is List) return data.cast<Map<String, dynamic>>();
    return const [];
  }

  // ------------------------------------------------------------- owner
  Future<OwnerDashboard> ownerDashboard() async =>
      OwnerDashboard.fromJson((await api.get('/api/dashboard')).data);

  Future<List<Customer>> customers({String? search, bool? withDues}) async {
    final res = await api.get('/api/customers',
        query: {'search': search, 'withDues': withDues, 'pageSize': 200});
    return _items(res.data).map(Customer.fromJson).toList();
  }

  Future<Customer> customer(int id) async =>
      Customer.fromJson((await api.get('/api/customers/$id')).data);

  Future<String> createCustomer(Map<String, dynamic> body) async =>
      (await api.post('/api/customers', body: body)).message;

  Future<String> updateCustomer(int id, Map<String, dynamic> body) async =>
      (await api.put('/api/customers/$id', body: body)).message;

  Future<String> setTrust(int id, bool trusted, double limit) async =>
      (await api.post('/api/customers/$id/trust',
              query: {'trusted': trusted, 'creditLimit': limit}))
          .message;

  Future<List<LedgerRow>> customerLedger(int id) async {
    final res = await api.get('/api/customers/$id/ledger');
    return _items(res.data).map(LedgerRow.fromJson).toList();
  }

  /// Counter scanning: the product with this barcode (or SKU).
  Future<Product> productByBarcode(String code) async => Product.fromJson(
      (await api.get('/api/products/barcode/${Uri.encodeComponent(code)}')).data);

  /// The shop's "Walk-in customer" for quick counter sales.
  Future<Customer> walkInCustomer() async =>
      Customer.fromJson((await api.post('/api/customers/walk-in')).data);

  Future<List<Product>> products({String? search, bool? lowStockOnly}) async {
    final res = await api.get('/api/products',
        query: {'search': search, 'lowStockOnly': lowStockOnly, 'pageSize': 200});
    return _items(res.data).map(Product.fromJson).toList();
  }

  Future<String> createProduct(Map<String, dynamic> body) async =>
      (await api.post('/api/products', body: body)).message;

  Future<String> updateProduct(int id, Map<String, dynamic> body) async =>
      (await api.put('/api/products/$id', body: body)).message;

  Future<List<Invoice>> invoices({int? customerId, String? status, String? search}) async {
    final res = await api.get('/api/invoices', query: {
      'customerId': customerId,
      'status': status,
      'search': search,
      'pageSize': 100,
    });
    return _items(res.data).map(Invoice.fromJson).toList();
  }

  Future<Invoice> invoice(int id) async =>
      Invoice.fromJson((await api.get('/api/invoices/$id')).data);

  Future<ApiResult<dynamic>> createInvoice(Map<String, dynamic> body) =>
      api.post('/api/invoices', body: body);

  Future<Map<String, dynamic>> resendBill(int id) async =>
      (await api.post('/api/invoices/$id/send-whatsapp')).data
          as Map<String, dynamic>;

  Future<String> cancelInvoice(int id, String reason) async =>
      (await api.post('/api/invoices/$id/cancel', query: {'reason': reason})).message;

  Future<String> recordPayment(Map<String, dynamic> body) async =>
      (await api.post('/api/payments', body: body)).message;

  // ------------------------------------------------------------ credits
  Future<List<CreditGrant>> credits({int? customerId, String? status}) async {
    final res = await api.get('/api/credits',
        query: {'customerId': customerId, 'status': status, 'pageSize': 100});
    return _items(res.data).map(CreditGrant.fromJson).toList();
  }

  Future<ApiResult<dynamic>> issueCredit(Map<String, dynamic> body) =>
      api.post('/api/credits/issue', body: body);

  Future<String> cancelCredit(int id, String reason) async =>
      (await api.post('/api/credits/$id/cancel', query: {'reason': reason})).message;

  Future<List<CreditClaim>> claims({String? status}) async {
    final res =
        await api.get('/api/credits/claims', query: {'status': status, 'pageSize': 100});
    return _items(res.data).map(CreditClaim.fromJson).toList();
  }

  Future<String> processClaim(int id, bool approve, String? remarks) async =>
      (await api.post('/api/credits/claims/$id/process',
              body: {'approve': approve, 'remarks': remarks}))
          .message;

  // ----------------------------------------------------------- customer
  Future<CustomerDashboard> myDashboard() async =>
      CustomerDashboard.fromJson((await api.get('/api/my/dashboard')).data);

  Future<List<Invoice>> myBills({int? businessId, bool? unpaidOnly}) async {
    final res = await api.get('/api/my/bills',
        query: {'businessId': businessId, 'unpaidOnly': unpaidOnly, 'pageSize': 100});
    return _items(res.data).map(Invoice.fromJson).toList();
  }

  Future<Invoice> myBill(int id) async =>
      Invoice.fromJson((await api.get('/api/my/bills/$id')).data);

  Future<List<CreditGrant>> myCredits({bool availableOnly = false}) async {
    final res =
        await api.get('/api/my/credits', query: {'availableOnly': availableOnly});
    return _items(res.data).map(CreditGrant.fromJson).toList();
  }

  Future<String> claimCredit(int grantId, double? amount, String? remarks) async =>
      (await api.post('/api/my/credits/claim', body: {
        'creditGrantId': grantId,
        'amount': amount,
        'remarks': remarks,
      }))
          .message;

  Future<List<CreditClaim>> myClaims() async {
    final res = await api.get('/api/my/claims');
    return _items(res.data).map(CreditClaim.fromJson).toList();
  }

  Future<String> cancelMyClaim(int id) async =>
      (await api.post('/api/my/claims/$id/cancel')).message;

  Future<List<LedgerRow>> myLedger({int? businessId}) async {
    final res = await api.get('/api/my/ledger', query: {'businessId': businessId});
    return _items(res.data).map(LedgerRow.fromJson).toList();
  }

  // -------------------------------------------------------------- admin
  Future<AdminDashboard> adminDashboard() async =>
      AdminDashboard.fromJson((await api.get('/api/admin/dashboard')).data);

  Future<List<AdminBusiness>> adminBusinesses({String? search}) async {
    final res = await api
        .get('/api/admin/businesses', query: {'search': search, 'pageSize': 100});
    return _items(res.data).map(AdminBusiness.fromJson).toList();
  }

  Future<String> toggleBusiness(int id) async =>
      (await api.post('/api/admin/businesses/$id/toggle-active')).message;

  Future<List<AdminUser>> adminUsers({String? role, String? search}) async {
    final res = await api.get('/api/admin/users',
        query: {'role': role, 'search': search, 'pageSize': 200});
    return _items(res.data).map(AdminUser.fromJson).toList();
  }

  Future<String> toggleUser(int id) async =>
      (await api.post('/api/admin/users/$id/toggle-active')).message;

  Future<String> resetPassword(int id, String newPassword) async =>
      (await api.post('/api/admin/users/$id/reset-password',
              body: {'newPassword': newPassword}))
          .message;

  Future<List<Customer>> adminCustomers({String? search}) async {
    final res = await api
        .get('/api/admin/customers', query: {'search': search, 'pageSize': 200});
    return _items(res.data).map(Customer.fromJson).toList();
  }

  Future<List<WhatsAppLogRow>> whatsAppLog({String? status}) async {
    final res =
        await api.get('/api/admin/whatsapp', query: {'status': status, 'pageSize': 100});
    return _items(res.data).map(WhatsAppLogRow.fromJson).toList();
  }

  Future<AdminUserDetail> adminUserDetail(int id) async =>
      AdminUserDetail.fromJson((await api.get('/api/admin/users/$id')).data);

  Future<AdminCustomerDetail> adminCustomerDetail(int id) async =>
      AdminCustomerDetail.fromJson((await api.get('/api/admin/customers/$id')).data);

  // ------------------------------------------------------------ lookup
  Future<CustomerInsight> lookupCustomer(String mobile) async =>
      CustomerInsight.fromJson((await api.get('/api/lookup/customer/$mobile')).data);

  // -------------------------------------------------- customer payments
  Future<List<PaymentRow>> myPayments({int? businessId}) async {
    final res = await api.get('/api/my/payments', query: {'businessId': businessId});
    return _items(res.data).map(PaymentRow.fromJson).toList();
  }

  // -------------------------------------------------------- preferences
  Future<UserProfile> savePreferences(String themeMode, String themeName) async =>
      UserProfile.fromJson((await api.put('/api/auth/preferences',
              body: {'themeMode': themeMode, 'themeName': themeName}))
          .data);

  // ------------------------------------------------------- shop UPI / QR
  /// Customer: the shop's UPI ID, to show the QR and open a UPI app.
  Future<ShopUpi> myShopUpi(int businessId) async =>
      ShopUpi.fromJson((await api.get('/api/my/shops/$businessId/upi')).data);

  /// Owner: their own UPI settings.
  Future<ShopUpi> shopUpi() async => ShopUpi.fromJson((await api.get('/api/shopupi')).data);

  Future<ApiResult<dynamic>> saveShopUpi(String upiId, String upiName) =>
      api.put('/api/shopupi', body: {'upiId': upiId, 'upiName': upiName});

  // ---------------------------------------------------- UPI payment proofs
  /// Customer sends the UPI screenshot to the shop.
  Future<String> submitPaymentProof({
    required int businessId,
    required double amount,
    int? invoiceId,
    String? referenceNo,
    String? note,
    List<int>? imageBytes,
    String? imageName,
    String? imageContentType,
  }) async {
    final fields = <String, String>{
      'businessId': '$businessId',
      'amount': '$amount',
      if (invoiceId != null) 'invoiceId': '$invoiceId',
      if (referenceNo != null && referenceNo.isNotEmpty) 'referenceNo': referenceNo,
      if (note != null && note.isNotEmpty) 'note': note,
    };

    final res = await api.postMultipart(
      '/api/my/payment-proofs',
      fields: fields,
      fileBytes: imageBytes,
      fileField: imageBytes == null ? null : 'screenshot',
      fileName: imageName,
      fileContentType: imageContentType,
    );
    return res.message;
  }

  Future<List<PaymentProof>> myPaymentProofs() async {
    final res = await api.get('/api/my/payment-proofs');
    return _items(res.data).map(PaymentProof.fromJson).toList();
  }

  Future<String> cancelMyProof(int id) async =>
      (await api.post('/api/my/payment-proofs/$id/cancel')).message;

  /// Shop owner's queue of screenshots to confirm.
  Future<List<PaymentProof>> paymentProofs({String? status}) async {
    final res = await api
        .get('/api/payment-proofs', query: {'status': status, 'pageSize': 100});
    return _items(res.data).map(PaymentProof.fromJson).toList();
  }

  Future<Uint8List> proofImage(int id) => api.getBytes('/api/payment-proofs/$id/image');

  Future<ApiResult<dynamic>> processProof(int id, bool approve, String? remarks) =>
      api.post('/api/payment-proofs/$id/process',
          body: {'approve': approve, 'remarks': remarks, 'sendWhatsApp': true});

  // ---------------------------------------------------------- statements
  Future<Statement> customerStatement(int customerId) async =>
      Statement.fromJson((await api.get('/api/customers/$customerId/statement')).data);

  Future<Map<String, dynamic>> sendStatement(int customerId) async =>
      (await api.post('/api/customers/$customerId/send-statement')).data
          as Map<String, dynamic>;

  Future<Statement> myStatement(int businessId) async => Statement.fromJson(
      (await api.get('/api/my/statement', query: {'businessId': businessId})).data);

  // ------------------------------------------------------------ expenses
  static String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<ExpenseSummary> expenses({DateTime? from, DateTime? to, int? businessId}) async =>
      ExpenseSummary.fromJson((await api.get('/api/expenses', query: {
        // Whole local days: from midnight, up to (not including) the day after `to`.
        'from': from == null ? null : DateTime(from.year, from.month, from.day).toUtc().toIso8601String(),
        'to': to == null
            ? null
            : DateTime(to.year, to.month, to.day).add(const Duration(days: 1)).toUtc().toIso8601String(),
        'businessId': businessId,
      }))
          .data);

  Future<List<String>> expenseCategories() async =>
      ((await api.get('/api/expenses/categories')).data as List).cast<String>();

  Future<String> createExpense(Map<String, dynamic> body) async =>
      (await api.post('/api/expenses', body: body)).message;

  Future<String> cancelExpense(int id) async =>
      (await api.post('/api/expenses/$id/cancel')).message;

  // ----------------------------------------------------- admin analytics
  Future<Analytics> adminAnalytics(
          {DateTime? from, DateTime? to, bool all = false, int? businessId}) async =>
      Analytics.fromJson((await api.get('/api/admin/analytics', query: {
        'from': from == null ? null : _day(from),
        'to': to == null ? null : _day(to),
        'all': all ? true : null,
        'businessId': businessId,
      }))
          .data);

  Future<List<CustomerPerson>> adminPeople({String? search, int? minShops}) async {
    final res = await api.get('/api/admin/people',
        query: {'search': search, 'minShops': minShops});
    return _items(res.data).map(CustomerPerson.fromJson).toList();
  }

  Future<CustomerPersonDetail> adminPerson(String mobile) async =>
      CustomerPersonDetail.fromJson((await api.get('/api/admin/people/$mobile')).data);
}
