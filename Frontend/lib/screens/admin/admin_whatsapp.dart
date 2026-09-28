import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

class AdminWhatsAppTab extends StatefulWidget {
  const AdminWhatsAppTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<AdminWhatsAppTab> createState() => _AdminWhatsAppTabState();
}

class _AdminWhatsAppTabState extends State<AdminWhatsAppTab> {
  String? _status;
  late Future<List<WhatsAppLogRow>> _future = widget.repo.whatsAppLog();

  Future<void> _reload() async {
    setState(() => _future = widget.repo.whatsAppLog(status: _status));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            children: [
              for (final s in const [null, 'Sent', 'Queued', 'Failed'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(s ?? 'All'),
                    selected: _status == s,
                    onSelected: (_) {
                      setState(() => _status = s);
                      _reload();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncBody<List<WhatsAppLogRow>>(
            future: _future,
            onRefresh: _reload,
            builder: (context, list) {
              if (list.isEmpty) {
                return ListView(
                  children: const [
                    SizedBox(height: 120),
                    EmptyState(
                      icon: Icons.chat_outlined,
                      title: 'No messages yet',
                      subtitle: 'Bills and credit alerts show up here',
                    ),
                  ],
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final m = list[i];
                  return Card(
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Icon(_icon(m.template), size: 21),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text('+91 ${m.toMobile}',
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          StatusPill(m.status),
                        ],
                      ),
                      subtitle: Text(
                        '${_label(m.template)}'
                        '${m.businessName == null ? '' : '  -  ${m.businessName}'}'
                        '  -  ${relative(m.createdAt)}',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(m.body,
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        height: 1.45,
                                        fontFamily: 'monospace')),
                              ),
                              if ((m.errorMessage ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text('Error: ${m.errorMessage}',
                                    style: TextStyle(
                                        fontSize: 12, color: scheme.error)),
                              ],
                              if ((m.deepLink ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: () =>
                                        openWhatsApp(context, m.deepLink),
                                    icon: const Icon(Icons.open_in_new, size: 18),
                                    label: const Text('Open in WhatsApp'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  static IconData _icon(String template) => switch (template) {
        'Bill' => Icons.receipt_long,
        'CreditIssued' => Icons.card_giftcard,
        'ClaimRequested' => Icons.hourglass_top,
        'ClaimApproved' => Icons.check_circle_outline,
        'ClaimRejected' => Icons.cancel_outlined,
        'PaymentReceipt' => Icons.payments_outlined,
        _ => Icons.chat_bubble_outline,
      };

  static String _label(String template) => switch (template) {
        'Bill' => 'Bill',
        'CreditIssued' => 'Credit given',
        'ClaimRequested' => 'Claim requested',
        'ClaimApproved' => 'Claim approved',
        'ClaimRejected' => 'Claim rejected',
        'PaymentReceipt' => 'Payment receipt',
        'Welcome' => 'Welcome',
        _ => template,
      };
}

