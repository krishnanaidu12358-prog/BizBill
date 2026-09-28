// Expenses, the Super Admin analytics dashboard and customers grouped by person.

import 'admin_models.dart';
import 'models.dart';

double _d(dynamic v) => v == null ? 0 : (v as num).toDouble();
int _i(dynamic v) => v == null ? 0 : (v as num).toInt();

List<T> _list<T>(dynamic raw, T Function(Map<String, dynamic>) make) =>
    ((raw as List?) ?? []).map((e) => make(e as Map<String, dynamic>)).toList();

// ----------------------------- expenses --------------------------------

class Expense {
  Expense({
    required this.id,
    required this.category,
    required this.amount,
    required this.expenseDate,
    required this.paymentMode,
    this.businessName = '',
    this.paidTo,
    this.note,
  });

  final int id;
  final String category;
  final double amount;
  final String expenseDate;
  final String paymentMode;
  final String businessName;
  final String? paidTo;
  final String? note;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
        id: _i(j['id']),
        category: j['category'] ?? '',
        amount: _d(j['amount']),
        expenseDate: j['expenseDate'] ?? '',
        paymentMode: j['paymentMode'] ?? '',
        businessName: j['businessName'] ?? '',
        paidTo: j['paidTo'],
        note: j['note'],
      );
}

class ExpenseSummary {
  ExpenseSummary({
    required this.total,
    required this.count,
    required this.byCategory,
    required this.items,
  });

  final double total;
  final int count;
  final List<NamedAmount> byCategory;
  final List<Expense> items;

  factory ExpenseSummary.fromJson(Map<String, dynamic> j) => ExpenseSummary(
        total: _d(j['total']),
        count: _i(j['count']),
        byCategory: _list(j['byCategory'], NamedAmount.fromJson),
        items: _list(j['items'], Expense.fromJson),
      );
}

// ----------------------------- analytics -------------------------------

class NamedAmount {
  NamedAmount({required this.name, required this.amount, required this.count});

  final String name;
  final double amount;
  final int count;

  factory NamedAmount.fromJson(Map<String, dynamic> j) => NamedAmount(
        name: j['name'] ?? '',
        amount: _d(j['amount']),
        count: _i(j['count']),
      );
}

class TrendPoint {
  TrendPoint({
    required this.label,
    required this.sales,
    required this.collected,
    required this.expenses,
    required this.bills,
    required this.newCustomers,
  });

  final String label;
  final double sales;
  final double collected;
  final double expenses;
  final int bills;
  final int newCustomers;

  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        label: j['label'] ?? '',
        sales: _d(j['sales']),
        collected: _d(j['collected']),
        expenses: _d(j['expenses']),
        bills: _i(j['bills']),
        newCustomers: _i(j['newCustomers']),
      );
}

class ShopPerformance {
  ShopPerformance({
    required this.businessId,
    required this.ownerUserId,
    required this.shopName,
    required this.sales,
    required this.expenses,
    required this.net,
    required this.receivable,
    required this.bills,
    required this.customers,
    this.ownerName,
    this.city,
  });

  final int businessId;
  final int ownerUserId;
  final String shopName;
  final double sales;
  final double expenses;
  final double net;
  final double receivable;
  final int bills;
  final int customers;
  final String? ownerName;
  final String? city;

  factory ShopPerformance.fromJson(Map<String, dynamic> j) => ShopPerformance(
        businessId: _i(j['businessId']),
        ownerUserId: _i(j['ownerUserId']),
        shopName: j['shopName'] ?? '',
        sales: _d(j['sales']),
        expenses: _d(j['expenses']),
        net: _d(j['net']),
        receivable: _d(j['receivable']),
        bills: _i(j['bills']),
        customers: _i(j['customers']),
        ownerName: j['ownerName'],
        city: j['city'],
      );
}

class AnalyticsKpis {
  AnalyticsKpis(this.j);

  final Map<String, dynamic> j;

  double get grossSales => _d(j['grossSales']);
  double get discounts => _d(j['discounts']);
  double get tax => _d(j['tax']);
  double get collected => _d(j['collected']);
  double get expenditure => _d(j['expenditure']);
  double get net => _d(j['net']);
  double get receivable => _d(j['receivable']);
  double get creditIssued => _d(j['creditIssued']);
  int get bills => _i(j['bills']);
  double get averageBill => _d(j['averageBill']);
  int get shops => _i(j['shops']);
  int get activeShops => _i(j['activeShops']);
  int get shopOwners => _i(j['shopOwners']);
  int get customers => _i(j['customers']);
  int get customerRecords => _i(j['customerRecords']);
  int get customersWithApp => _i(j['customersWithApp']);
  int get multiShopCustomers => _i(j['multiShopCustomers']);
}

class Analytics {
  Analytics({
    required this.from,
    required this.to,
    required this.granularity,
    required this.kpis,
    required this.trend,
    required this.topShops,
    required this.paymentModes,
    required this.expenseCategories,
    required this.billStatus,
    required this.topProducts,
  });

  final String from;
  final String to;
  final String granularity;
  final AnalyticsKpis kpis;
  final List<TrendPoint> trend;
  final List<ShopPerformance> topShops;
  final List<NamedAmount> paymentModes;
  final List<NamedAmount> expenseCategories;
  final List<NamedAmount> billStatus;
  final List<NamedAmount> topProducts;

  factory Analytics.fromJson(Map<String, dynamic> j) => Analytics(
        from: j['from'] ?? '',
        to: j['to'] ?? '',
        granularity: j['granularity'] ?? 'Day',
        kpis: AnalyticsKpis((j['kpis'] as Map<String, dynamic>?) ?? {}),
        trend: _list(j['trend'], TrendPoint.fromJson),
        topShops: _list(j['topShops'], ShopPerformance.fromJson),
        paymentModes: _list(j['paymentModes'], NamedAmount.fromJson),
        expenseCategories: _list(j['expenseCategories'], NamedAmount.fromJson),
        billStatus: _list(j['billStatus'], NamedAmount.fromJson),
        topProducts: _list(j['topProducts'], NamedAmount.fromJson),
      );
}

// --------------------- customers grouped by person ---------------------

class CustomerPerson {
  CustomerPerson({
    required this.mobile,
    required this.name,
    required this.shopCount,
    required this.totalOutstanding,
    required this.totalCredit,
    required this.totalBilled,
    required this.billCount,
    required this.hasAppAccount,
    required this.isTrustedAnywhere,
    required this.firstSeen,
  });

  final String mobile;
  final String name;
  final int shopCount;
  final double totalOutstanding;
  final double totalCredit;
  final double totalBilled;
  final int billCount;
  final bool hasAppAccount;
  final bool isTrustedAnywhere;
  final String firstSeen;

  factory CustomerPerson.fromJson(Map<String, dynamic> j) => CustomerPerson(
        mobile: j['mobile'] ?? '',
        name: j['name'] ?? '',
        shopCount: _i(j['shopCount']),
        totalOutstanding: _d(j['totalOutstanding']),
        totalCredit: _d(j['totalCredit']),
        totalBilled: _d(j['totalBilled']),
        billCount: _i(j['billCount']),
        hasAppAccount: j['hasAppAccount'] == true,
        isTrustedAnywhere: j['isTrustedAnywhere'] == true,
        firstSeen: j['firstSeen'] ?? '',
      );
}

class CustomerPersonShop {
  CustomerPersonShop({
    required this.customerId,
    required this.businessId,
    required this.shopName,
    required this.shopMobile,
    required this.ownerUserId,
    required this.nameAtShop,
    required this.isTrusted,
    required this.creditLimit,
    required this.outstanding,
    required this.creditAvailable,
    required this.totalBilled,
    required this.totalPaid,
    required this.billCount,
    required this.customerSince,
    this.shopCity,
    this.ownerName,
    this.lastBillOn,
  });

  final int customerId;
  final int businessId;
  final String shopName;
  final String shopMobile;
  final int ownerUserId;
  final String nameAtShop;
  final bool isTrusted;
  final double creditLimit;
  final double outstanding;
  final double creditAvailable;
  final double totalBilled;
  final double totalPaid;
  final int billCount;
  final String customerSince;
  final String? shopCity;
  final String? ownerName;
  final String? lastBillOn;

  factory CustomerPersonShop.fromJson(Map<String, dynamic> j) => CustomerPersonShop(
        customerId: _i(j['customerId']),
        businessId: _i(j['businessId']),
        shopName: j['shopName'] ?? '',
        shopMobile: j['shopMobile'] ?? '',
        ownerUserId: _i(j['ownerUserId']),
        nameAtShop: j['nameAtShop'] ?? '',
        isTrusted: j['isTrusted'] == true,
        creditLimit: _d(j['creditLimit']),
        outstanding: _d(j['outstanding']),
        creditAvailable: _d(j['creditAvailable']),
        totalBilled: _d(j['totalBilled']),
        totalPaid: _d(j['totalPaid']),
        billCount: _i(j['billCount']),
        customerSince: j['customerSince'] ?? '',
        shopCity: j['shopCity'],
        ownerName: j['ownerName'],
        lastBillOn: j['lastBillOn'],
      );
}

class CustomerPersonDetail {
  CustomerPersonDetail({
    required this.person,
    required this.insight,
    required this.shops,
    required this.recentBills,
    this.account,
  });

  final CustomerPerson person;
  final CustomerInsight insight;
  final List<CustomerPersonShop> shops;
  final List<Invoice> recentBills;
  final AdminUser? account;

  factory CustomerPersonDetail.fromJson(Map<String, dynamic> j) => CustomerPersonDetail(
        person: CustomerPerson.fromJson(j['person'] as Map<String, dynamic>),
        insight: CustomerInsight.fromJson(
            (j['insight'] as Map<String, dynamic>?) ?? <String, dynamic>{}),
        shops: _list(j['shops'], CustomerPersonShop.fromJson),
        recentBills: _list(j['recentBills'], Invoice.fromJson),
        account: j['account'] == null
            ? null
            : AdminUser.fromJson(j['account'] as Map<String, dynamic>),
      );
}
