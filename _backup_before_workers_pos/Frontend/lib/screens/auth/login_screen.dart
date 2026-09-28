import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/app_config.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/brand_logo.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().login(_mobile.text.trim(), _password.text);
      // RootRouter swaps the screen once the session notifies.
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fill(String mobile, String password) {
    _mobile.text = mobile;
    _password.text = password;
    setState(() {});
  }

  Future<void> _serverDialog() async {
    final controller = TextEditingController(text: AppConfig.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('API server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Android emulator: http://10.0.2.2:5000\n'
              'Real phone: http://<your-PC-LAN-IP>:5000\n'
              'Windows/desktop: http://localhost:5000',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Base URL'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(minimumSize: const Size(90, 40)),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      await AppConfig.setBaseUrl(result);
      if (mounted) {
        setState(() {});
        showSnack(context, 'Server set to ${AppConfig.baseUrl}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    const Center(child: BrandLogo(height: 170)),
                    const SizedBox(height: 10),
                    Text(
                      'Billing, Udhaar, UPI and credits for your shop',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
                    ),
                    const SizedBox(height: 34),

                    TextFormField(
                      controller: _mobile,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixText: '+91  ',
                        counterText: '',
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                      validator: (v) => (v ?? '').trim().length != 10
                          ? 'Enter the 10-digit mobile number'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onFieldSubmitted: (_) => _submit(),
                      validator: (v) =>
                          (v ?? '').isEmpty ? 'Enter your password' : null,
                    ),
                    const SizedBox(height: 22),

                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? CoinLoader(size: 22)
                          : const Text('Log in'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const RegisterScreen()),
                              ),
                      child: const Text('New here? Create an account'),
                    ),

                    const SizedBox(height: 14),
                    const Divider(),
                    const SizedBox(height: 10),
                    Text('Demo accounts - tap to fill',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _DemoChip(
                          label: 'Super Admin',
                          icon: Icons.shield_outlined,
                          onTap: () => _fill('9999900001', 'Admin@123'),
                        ),
                        _DemoChip(
                          label: 'Shop: Electricals',
                          icon: Icons.store_outlined,
                          onTap: () => _fill('9999911111', 'User@123'),
                        ),
                        _DemoChip(
                          label: 'Shop: Kirana',
                          icon: Icons.store_outlined,
                          onTap: () => _fill('9999922222', 'User@123'),
                        ),
                        _DemoChip(
                          label: 'Customer: Ramesh',
                          icon: Icons.person_outline,
                          onTap: () => _fill('9876500001', 'Cust@123'),
                        ),
                        _DemoChip(
                          label: 'Customer: Suresh',
                          icon: Icons.person_outline,
                          onTap: () => _fill('9876500002', 'Cust@123'),
                        ),
                        _DemoChip(
                          label: 'Customer: Lakshmi',
                          icon: Icons.person_outline,
                          onTap: () => _fill('9876500003', 'Cust@123'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextButton.icon(
                      onPressed: _serverDialog,
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: Text('Server: ${AppConfig.baseUrl}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.label, required this.icon, required this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onTap,
      backgroundColor:
          Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
    );
  }
}
