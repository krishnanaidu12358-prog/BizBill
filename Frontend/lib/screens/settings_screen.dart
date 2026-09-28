import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/theme.dart';
import '../services/repo.dart';
import '../state/appearance.dart';
import '../state/session.dart';
import '../widgets/brand_logo.dart';
import '../widgets/common.dart';

/// Appearance and account settings. Shared by all three roles.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saving = false;

  Future<void> _push() async {
    final appearance = context.read<Appearance>();
    final session = context.read<Session>();

    setState(() => _saving = true);
    try {
      final profile = await Repo(session.api)
          .savePreferences(appearance.modeName, appearance.palette);
      await session.updateCachedProfile(profile);
    } on ApiException catch (e) {
      // The look already changed locally; only the sync to the account failed.
      if (mounted) {
        showSnack(context, 'Saved on this device only: ${e.message}', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final session = context.read<Session>();
    final current = TextEditingController();
    final next = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: current,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(minimumSize: const Size(110, 40)),
            child: const Text('Change'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    if (next.text.length < 6) {
      if (mounted) {
        showSnack(context, 'New password must be at least 6 characters.', error: true);
      }
      return;
    }

    try {
      final res = await session.api.post('/api/auth/change-password',
          body: {'currentPassword': current.text, 'newPassword': next.text});
      if (mounted) showSnack(context, res.message);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = context.watch<Appearance>();
    final session = context.watch<Session>();
    final user = session.user;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: CoinLoader(size: 18),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          if (user != null)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  radius: 24,
                  child: Text(
                    user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase(),
                    style: const TextStyle(fontSize: 19),
                  ),
                ),
                title: Text(user.fullName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('+91 ${user.mobile}\n${_roleLabel(user.role)}'
                    '${user.businessName == null ? '' : ' - ${user.businessName}'}'),
                isThreeLine: true,
              ),
            ),

          const SizedBox(height: 22),
          const _Heading('Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mode',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system,
                          icon: Icon(Icons.brightness_auto),
                          label: Text('System')),
                      ButtonSegment(
                          value: ThemeMode.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light')),
                      ButtonSegment(
                          value: ThemeMode.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark')),
                    ],
                    selected: {appearance.mode},
                    onSelectionChanged: (s) async {
                      await appearance.setMode(s.first);
                      await _push();
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),
          const _Heading('Theme colour'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  for (var i = 0; i < appPalettes.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _PaletteTile(
                      palette: appPalettes[i],
                      selected: appearance.palette == appPalettes[i].key,
                      onTap: () async {
                        await appearance.setPalette(appPalettes[i].key);
                        await _push();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 22),
          const _Heading('Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _changePassword,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: const Text('API server'),
                  subtitle: Text(AppConfig.baseUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: scheme.error),
                  title: Text('Log out', style: TextStyle(color: scheme.error)),
                  onTap: () async {
                    await context.read<Session>().logout();
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          const Center(child: BrandLogo(height: 70, markOnly: true)),
          const SizedBox(height: 6),
          Center(
            child: Text('BizBill 1.0  ·  Easy Billing. Better Business.',
                style: TextStyle(fontSize: 12, color: scheme.outline)),
          ),
        ],
      ),
    );
  }

  static String _roleLabel(String role) => switch (role) {
        'SuperAdmin' => 'Super Admin',
        'BusinessUser' => 'Shop owner',
        'Customer' => 'Customer',
        _ => role,
      };
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: Theme.of(context).brightness,
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? preview.primary : scheme.outlineVariant.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
          color: selected ? preview.primary.withValues(alpha: 0.06) : null,
        ),
        child: Row(
          children: [
            // A miniature of the scheme this palette produces.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: preview.primary,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: 14,
                    margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    decoration: BoxDecoration(
                      color: preview.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(palette.label,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(palette.blurb,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: preview.primary),
          ],
        ),
      ),
    );
  }
}

