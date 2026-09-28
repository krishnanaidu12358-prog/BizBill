import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../models/workforce_models.dart';
import '../../services/repo.dart';
import '../../widgets/common.dart';

/// Add or edit a worker. On add, the owner can also give them a counter login.
class WorkerFormScreen extends StatefulWidget {
  const WorkerFormScreen({super.key, required this.repo, this.worker});

  final Repo repo;
  final Worker? worker;

  @override
  State<WorkerFormScreen> createState() => _WorkerFormScreenState();
}

class _WorkerFormScreenState extends State<WorkerFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.worker?.name);
  late final _mobile = TextEditingController(text: widget.worker?.mobile);
  late final _designation = TextEditingController(text: widget.worker?.designation);
  late final _salary = TextEditingController(
      text: widget.worker == null ? '' : widget.worker!.salaryAmount.toStringAsFixed(0));
  late final _address = TextEditingController(text: widget.worker?.address);
  final _password = TextEditingController();

  late String _salaryType = widget.worker?.salaryType ?? 'Monthly';
  late bool _canUdhaar = widget.worker?.canGiveUdhaar ?? false;
  late DateTime _joinDate =
      widget.worker == null ? DateTime.now() : DateTime.parse(widget.worker!.joinDate);
  bool _giveLogin = true;
  bool _busy = false;

  bool get _isEdit => widget.worker != null;

  static const _roles = ['Cashier', 'Sales', 'Helper', 'Store keeper', 'Delivery', 'Manager'];

  @override
  void dispose() {
    for (final c in [_name, _mobile, _designation, _salary, _address, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'mobile': _mobile.text.trim(),
      'designation': _designation.text.trim().isEmpty ? null : _designation.text.trim(),
      'salaryType': _salaryType,
      'salaryAmount': double.tryParse(_salary.text.trim()) ?? 0,
      'joinDate': apiDay(_joinDate),
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'canGiveUdhaar': _canUdhaar,
      if (!_isEdit && _giveLogin) 'loginPassword': _password.text,
    };
    try {
      final msg = _isEdit
          ? await widget.repo.updateWorker(widget.worker!.id, body)
          : await widget.repo.createWorker(body);
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
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit worker' : 'Add worker')),
      body: ResponsiveCenter(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the name' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                enabled: !(_isEdit && widget.worker!.hasLogin),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Mobile',
                  prefixText: '+91 ',
                  prefixIcon: const Icon(Icons.phone_outlined),
                  helperText: _isEdit && widget.worker!.hasLogin ? 'Used for login - cannot change' : null,
                ),
                validator: (v) => RegExp(r'^\d{10}$').hasMatch(v ?? '') ? null : 'Enter 10 digits',
              ),
              TextFormField(
                controller: _designation,
                decoration: const InputDecoration(labelText: 'Role / designation', prefixIcon: Icon(Icons.work_outline)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in _roles)
                    ActionChip(label: Text(r), onPressed: () => setState(() => _designation.text = r)),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'Monthly', label: Text('Monthly salary'), icon: Icon(Icons.calendar_month)),
                  ButtonSegment(value: 'Daily', label: Text('Daily wage'), icon: Icon(Icons.today)),
                ],
                selected: {_salaryType},
                onSelectionChanged: (s) => setState(() => _salaryType = s.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _salary,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                  labelText: _salaryType == 'Daily' ? 'Pay per day' : 'Salary per month',
                  prefixText: '₹ ',
                ),
                validator: (v) => double.tryParse((v ?? '').trim()) == null ? 'Enter the amount' : null,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Joined on'),
                subtitle: Text(DateFormat('dd MMM yyyy').format(_joinDate)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _joinDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _joinDate = d);
                },
              ),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Address (optional)', prefixIcon: Icon(Icons.home_outlined)),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Can give Udhaar'),
                subtitle: const Text('Allow this worker to leave an unpaid balance on a trusted customer\'s bill'),
                value: _canUdhaar,
                onChanged: (v) => setState(() => _canUdhaar = v),
              ),
              if (!_isEdit) ...[
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Give a counter login'),
                  subtitle: const Text('They log in with this mobile number and can bill at the counter, '
                      'check in and see their own sales. They cannot see reports, stock costs or other bills.'),
                  value: _giveLogin,
                  onChanged: (v) => setState(() => _giveLogin = v),
                ),
                if (_giveLogin)
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Login password', prefixIcon: Icon(Icons.lock_outline)),
                    validator: (v) => _giveLogin && (v ?? '').length < 6 ? 'At least 6 characters' : null,
                  ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_isEdit ? 'Save changes' : 'Add worker'),
              ),
              if (_busy) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(color: scheme.primary)),
            ],
          ),
        ),
      ),
    );
  }
}
