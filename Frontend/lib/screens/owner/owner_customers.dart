import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';
import 'owner_customer_detail.dart';

class OwnerCustomersTab extends StatefulWidget {
  const OwnerCustomersTab({super.key, required this.repo});

  final Repo repo;

  @override
  State<OwnerCustomersTab> createState() => _OwnerCustomersTabState();
}

class _OwnerCustomersTabState extends State<OwnerCustomersTab> {
  final _search = TextEditingController();
  bool _duesOnly = false;
  late Future<List<Customer>> _future = widget.repo.customers();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _future = widget.repo.customers(
          search: _search.text.trim().isEmpty ? null : _search.text.trim(),
          withDues: _duesOnly ? true : null,
        ));
    try {
      await _future;
    } catch (_) {
      // AsyncBody renders the failure; the refresh gesture must not throw.
    }
  }

  Future<void> _addCustomer() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CustomerFormSheet(repo: widget.repo),
    );
    if (saved == true) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'Search name or mobile',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _reload,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Has Udhaar'),
                  selected: _duesOnly,
                  onSelected: (v) {
                    setState(() => _duesOnly = v);
                    _reload();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: AsyncBody<List<Customer>>(
              future: _future,
              onRefresh: _reload,
              builder: (context, list) {
                if (list.isEmpty) {
                  return ListView(
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.people_outline,
                        title: 'No customers yet',
                        subtitle: 'Add one with the + button',
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(c.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            if (c.isTrusted)
                              Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(Icons.verified,
                                    size: 15, color: moneyPositive(context)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text('+91 ${c.mobile}'
                                '${c.hasAppAccount ? '  -  has app' : ''}'),
                            if (c.creditBalance > 0)
                              Text('Credit available ${money(c.creditBalance)}',
                                  style: TextStyle(
                                      fontSize: 12.5,
                                      color: moneyPositive(context),
                                      fontWeight: FontWeight.w600)),
                          ],
                        ),
                        isThreeLine: c.creditBalance > 0,
                        trailing: c.outstandingBalance > 0
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(money(c.outstandingBalance),
                                      style: TextStyle(
                                          color: moneyNegative(context),
                                          fontWeight: FontWeight.w700)),
                                  const Text('Udhaar',
                                      style: TextStyle(fontSize: 11)),
                                ],
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailScreen(
                                  repo: widget.repo, customerId: c.id),
                            ),
                          );
                          await _reload();
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'addCustomer',
        onPressed: _addCustomer,
        child: const Icon(Icons.person_add_alt),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

/// Add / edit a customer. The mobile number doubles as their login id.
class CustomerFormSheet extends StatefulWidget {
  const CustomerFormSheet({super.key, required this.repo, this.existing});

  final Repo repo;
  final Customer? existing;

  @override
  State<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<CustomerFormSheet> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _mobile = TextEditingController(text: widget.existing?.mobile ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _limit = TextEditingController(
      text: (widget.existing?.creditLimit ?? 0).toStringAsFixed(0));
  final _password = TextEditingController();
  late bool _trusted = widget.existing?.isTrusted ?? false;
  bool _busy = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _mobile, _address, _limit, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _busy = true);

    final body = {
      'name': _name.text.trim(),
      'mobile': _mobile.text.trim(),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'isTrusted': _trusted,
      'creditLimit': double.tryParse(_limit.text) ?? 0,
      if (!_isEdit && _password.text.isNotEmpty) 'initialPassword': _password.text,
    };

    try {
      final msg = _isEdit
          ? await widget.repo.updateCustomer(widget.existing!.id, body)
          : await widget.repo.createCustomer(body);
      if (!mounted) return;
      showSnack(context, msg);
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_isEdit ? 'Edit customer' : 'Add customer',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter the customer name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  prefixText: '+91  ',
                  counterText: '',
                  helperText: 'This is the customer\'s login id',
                ),
                validator: (v) =>
                    (v ?? '').trim().length != 10 ? 'Enter 10 digits' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Address (optional)'),
              ),
              if (!_isEdit) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(
                    labelText: 'App password for the customer (optional)',
                    helperText: 'Leave blank and they can sign up themselves',
                  ),
                  validator: (v) => (v ?? '').isNotEmpty && v!.length < 6
                      ? 'Use at least 6 characters'
                      : null,
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _trusted,
                onChanged: (v) => setState(() => _trusted = v),
                title: const Text('Trusted customer'),
                subtitle: const Text(
                    'Required for Udhaar and for issuing credit',
                    style: TextStyle(fontSize: 12)),
              ),
              if (_trusted)
                TextFormField(
                  controller: _limit,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Credit limit',
                    prefixText: '₹ ',
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? CoinLoader(size: 22)
                    : Text(_isEdit ? 'Save changes' : 'Add customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

