import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../ui/widgets.dart';

/// Email + password login. There is no sign-up: the account is created in
/// Supabase (Authentication > Users), and public sign-ups are switched off.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      // The router sends us to the dashboard when the session appears.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = "Couldn't reach the server. Check your internet.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PageBody(
              maxWidth: 420,
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: c.primaryContainer,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Icon(Icons.eco, size: 48, color: c.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Plant Guard',
                          textAlign: TextAlign.center, style: text.headlineMedium),
                      const SizedBox(height: 4),
                      Text('Log in to see and water your plant',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant)),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _email,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enabled: !_busy,
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? 'Enter your email' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _showPassword ? 'Hide password' : 'Show password',
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () => setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        obscureText: !_showPassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        enabled: !_busy,
                        onFieldSubmitted: (_) => _login(),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Enter your password' : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        AlertBanner(icon: Icons.error_outline, title: _error!, error: true),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _login,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator.adaptive(strokeWidth: 2.5),
                              )
                            : const Text('Log in'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
