import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create account'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.store_outlined), text: 'I own a shop'),
              Tab(icon: Icon(Icons.person_outline), text: 'I am a customer'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_BusinessForm(), _CustomerForm()],
        ),
      ),
    );
  }
}

final _mobileInput = <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly];

String? _mobileValidator(String? v) =>
    (v ?? '').trim().length != 10 ? 'Enter the 10-digit mobile number' : null;

String? _passwordValidator(String? v) =>
    (v ?? '').length < 6 ? 'Use at least 6 characters' : null;

class _BusinessForm extends StatefulWidget {
  const _BusinessForm();

  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  final _key = GlobalKey<FormState>();
  final _shop = TextEditingController();
  final _owner = TextEditingController();
  final _mobile = TextEditingController();
  final _city = TextEditingController();
  final _gst = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String _type = 'Kirana';

  static const _types = [
    'Supermarket', 'Mart', 'Kirana', 'Retail', 'Electricals', 'Hardware', 'Pharmacy',
    'Restaurant', 'Bakery', 'Textiles', 'Footwear', 'Mobile shop', 'Stationery',
    'Wholesale', 'Services', 'Other',
  ];

  @override
  void dispose() {
    for (final c in [_shop, _owner, _mobile, _city, _gst, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().registerBusiness({
        'businessName': _shop.text.trim(),
        'businessType': _type,
        'ownerName': _owner.text.trim(),
        'mobile': _mobile.text.trim(),
        'city': _city.text.trim(),
        'gstNumber': _gst.text.trim().isEmpty ? null : _gst.text.trim(),
        'password': _password.text,
      });
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Form(
          key: _key,
          child: Column(
            children: [
              TextFormField(
                controller: _shop,
                decoration: const InputDecoration(
                    labelText: 'Shop / business name',
                    prefixIcon: Icon(Icons.storefront_outlined)),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter your shop name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(
                    labelText: 'Type of business', prefixIcon: Icon(Icons.category_outlined)),
                items: [for (final t in _types) DropdownMenuItem(value: t, child: Text(t))],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _owner,
                decoration: const InputDecoration(
                    labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: _mobileInput,
                decoration: const InputDecoration(
                  labelText: 'Mobile number (this is your login)',
                  prefixText: '+91  ',
                  counterText: '',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: _mobileValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(
                    labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _gst,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'GST number (optional)',
                    prefixIcon: Icon(Icons.receipt_long_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                validator: _passwordValidator,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? CoinLoader(size: 22)
                    : const Text('Create shop account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm();

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _mobile, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().registerCustomer({
        'fullName': _name.text.trim(),
        'mobile': _mobile.text.trim(),
        'password': _password.text,
      });
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: scheme.primaryContainer.withValues(alpha: 0.4),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Use the same mobile number your shop has on file. '
                    'Your bills and credits link to it automatically.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Form(
          key: _key,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Your name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: _mobileInput,
                decoration: const InputDecoration(
                  labelText: 'Mobile number (this is your login)',
                  prefixText: '+91  ',
                  counterText: '',
                  prefixIcon: Icon(Icons.phone_android),
                ),
                validator: _mobileValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                validator: _passwordValidator,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? CoinLoader(size: 22)
                    : const Text('Create customer account'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
