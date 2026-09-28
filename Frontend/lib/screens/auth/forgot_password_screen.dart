import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api_client.dart';
import '../../widgets/common.dart';

/// "Forgot password" for shop owners and customers.
///
/// Step 1: the mobile number - the API sends a 6-digit code to it on WhatsApp.
/// Step 2: the code and a new password. The code works for 10 minutes and five
/// tries. On success this closes and hands the mobile number back to the login
/// screen, so only the new password has to be typed.
///
/// Workers do not use this: their login is set by the shop owner, who can
/// change it from the Workers screen.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialMobile = ''});

  final String initialMobile;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  // Nobody is signed in here, so the calls go out without a token.
  final _api = ApiClient(tokenProvider: () => null);

  final _mobileKey = GlobalKey<FormState>();
  final _resetKey = GlobalKey<FormState>();
  late final TextEditingController _mobile;
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;
  String? _info;

  @override
  void initState() {
    super.initState();
    _mobile = TextEditingController(text: widget.initialMobile);
  }

  @override
  void dispose() {
    _mobile.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String _messageOf(ApiException e) {
    final errors = e.errors;
    if (errors != null && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return '${first.first}';
    }
    return e.message;
  }

  Future<void> _sendCode() async {
    if (!_mobileKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await _api.post('/api/auth/forgot-password',
          body: {'mobile': _mobile.text.trim()});
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _info = res.message;
      });
    } on ApiException catch (e) {
      if (mounted) showSnack(context, _messageOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!_resetKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final res = await _api.post('/api/auth/reset-password', body: {
        'mobile': _mobile.text.trim(),
        'code': _code.text.trim(),
        'newPassword': _password.text,
      });
      if (!mounted) return;
      showSnack(context, res.message.isEmpty ? 'Password changed.' : res.message);
      Navigator.pop(context, _mobile.text.trim());
    } on ApiException catch (e) {
      if (mounted) showSnack(context, _messageOf(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.lock_reset, size: 56, color: scheme.primary),
                  const SizedBox(height: 12),
                  Text(
                    _codeSent
                        ? 'Enter the 6-digit code and choose a new password'
                        : 'We will send a 6-digit code to your mobile on WhatsApp',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'For shop owners and customers. Workers: ask your shop owner to reset your login.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),

                  // ---------------- step 1: mobile
                  Form(
                    key: _mobileKey,
                    child: TextFormField(
                      controller: _mobile,
                      enabled: !_codeSent && !_busy,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixText: '+91  ',
                        counterText: '',
                        prefixIcon: Icon(Icons.phone_android),
                      ),
                      onFieldSubmitted: (_) => _sendCode(),
                      validator: (v) => (v ?? '').trim().length != 10
                          ? 'Enter the 10-digit mobile number'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!_codeSent)
                    FilledButton(
                      onPressed: _busy ? null : _sendCode,
                      child: _busy ? CoinLoader(size: 22) : const Text('Send code'),
                    ),

                  // ---------------- step 2: code + new password
                  if (_codeSent) ...[
                    if (_info != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_info!, style: const TextStyle(fontSize: 13, height: 1.4)),
                      ),
                    Form(
                      key: _resetKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            autofocus: true,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: const TextStyle(fontSize: 20, letterSpacing: 6),
                            decoration: const InputDecoration(
                              labelText: '6-digit code',
                              counterText: '',
                              prefixIcon: Icon(Icons.pin_outlined),
                            ),
                            validator: (v) => (v ?? '').trim().length != 6
                                ? 'Enter the 6-digit code from WhatsApp'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'New password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v ?? '').length < 6
                                ? 'Use at least 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _confirm,
                            obscureText: _obscure,
                            decoration: const InputDecoration(
                              labelText: 'Type the new password again',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            onFieldSubmitted: (_) => _reset(),
                            validator: (v) => v != _password.text
                                ? 'The two passwords are different'
                                : null,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _busy ? null : _reset,
                            child: _busy
                                ? CoinLoader(size: 22)
                                : const Text('Change password'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _codeSent = false;
                                          _info = null;
                                          _code.clear();
                                        }),
                                child: const Text('Change number'),
                              ),
                              TextButton(
                                onPressed: _busy ? null : _sendCode,
                                child: const Text('Send the code again'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
