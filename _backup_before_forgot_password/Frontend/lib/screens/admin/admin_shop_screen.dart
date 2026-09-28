import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/branding_image.dart';
import '../../widgets/common.dart';
import '../owner/owner_approvals.dart';
import '../owner/owner_bills.dart';
import '../owner/owner_credits.dart';
import '../owner/owner_customers.dart';
import '../owner/owner_dashboard.dart';
import '../owner/owner_expenses.dart';
import '../owner/owner_products.dart';
import '../owner/shop_profile_screen.dart';
import '../pos/pos_screen.dart';
import '../workers/workers_screen.dart';
import 'admin_user_detail.dart';

/// The Super Admin inside one shop - supermarket, mart, kirana, any type.
/// Every screen here is the owner's own screen, pinned to this shop, so the
/// admin sees and manages exactly what the owner does: profile and branding,
/// bills, counter billing, stock, customers, credits, workers and expenses.
class AdminShopScreen extends StatelessWidget {
  const AdminShopScreen({super.key, required this.repo, required this.business});

  /// The admin's own (unscoped) repo.
  final Repo repo;
  final AdminBusiness business;

  @override
  Widget build(BuildContext context) {
    final shop = Repo(repo.api.forBusiness(business.id));
    final scheme = Theme.of(context).colorScheme;

    void open(String title, Widget body, {bool wrap = true}) => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => wrap
                ? Scaffold(
                    appBar: AppBar(
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title),
                          Text(business.name,
                              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    body: body,
                  )
                : body,
          ),
        );

    final tiles = <_Tile>[
      _Tile(Icons.storefront_outlined, 'Profile, logo & signature', 'What prints on bills',
          () => open('', ShopProfileScreen(repo: shop, adminView: true), wrap: false)),
      _Tile(Icons.dashboard_outlined, 'Dashboard', 'Sales, dues, stock alerts',
          () => open('Dashboard', OwnerDashboardTab(repo: shop))),
      _Tile(Icons.receipt_long_outlined, 'All bills', 'Every bill, by any worker',
          () => open('Bills', OwnerBillsTab(repo: shop))),
      _Tile(Icons.point_of_sale, 'Counter billing', 'Bill on behalf of this shop',
          () => open('', PosScreen(repo: shop), wrap: false)),
      _Tile(Icons.inventory_2_outlined, 'Stock', 'Products, prices, barcodes',
          () => open('Stock', OwnerProductsTab(repo: shop))),
      _Tile(Icons.people_outline, 'Customers', 'Udhaar, trust, statements',
          () => open('Customers', OwnerCustomersTab(repo: shop))),
      _Tile(Icons.card_giftcard_outlined, 'Credits', 'Store credit and claims',
          () => open('Credits', OwnerCreditsTab(repo: shop))),
      _Tile(Icons.fact_check_outlined, 'Customer payments', 'UPI screenshots to approve',
          () => open('', PaymentApprovalsScreen(repo: shop), wrap: false)),
      _Tile(Icons.badge_outlined, 'Workers', 'Attendance, salary, sales by worker',
          () => open('', WorkersScreen(repo: shop), wrap: false)),
      _Tile(Icons.shopping_bag_outlined, 'Expenses', 'Spending and salary paid',
          () => open('', ExpensesScreen(repo: shop), wrap: false)),
      if (business.ownerUserId != 0)
        _Tile(Icons.manage_accounts_outlined, 'Owner account', 'Login, password, activity',
            () => open('', AdminUserDetailScreen(repo: repo, userId: business.ownerUserId), wrap: false)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Manage shop')),
      body: ResponsiveCenter(
        maxWidth: 980,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    BrandingImage(
                      url: business.logoUrl,
                      width: 64,
                      height: 64,
                      placeholder: InitialsAvatar(business.name, radius: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(business.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                          Text('${business.businessType}  ·  ${business.ownerName ?? ''}  ·  +91 ${business.mobile}'
                              '${(business.city ?? '').isEmpty ? '' : '  ·  ${business.city}'}',
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              StatusPill(business.isActive ? 'Active' : 'Cancelled'),
                              Chip(visualDensity: VisualDensity.compact, label: Text('${business.invoiceCount} bills')),
                              Chip(visualDensity: VisualDensity.compact, label: Text('Sales ${moneyShort(business.totalSales)}')),
                              Chip(visualDensity: VisualDensity.compact, label: Text('${business.workerCount} workers')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 820 ? 4 : c.maxWidth > 560 ? 3 : 2;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.35,
                children: [
                  for (final t in tiles)
                    Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: t.onTap,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(t.icon, color: scheme.primary, size: 28),
                              const Spacer(),
                              Text(t.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                              Text(t.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
            const SizedBox(height: 12),
            Text(
              'You are working inside this shop as Super Admin. Changes are recorded in the audit log.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile {
  const _Tile(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}
