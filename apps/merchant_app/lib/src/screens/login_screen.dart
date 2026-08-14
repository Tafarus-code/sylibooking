import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await widget.auth.signIn(_username.text, _password.text);
    // Routing is handled by the listener in MerchantApp; nothing to do here
    // beyond letting the error message rebuild.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: ListenableBuilder(
                listenable: widget.auth,
                builder: (context, _) {
                  final busy = widget.auth.busy;
                  return Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.storefront,
                          size: 56,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Sylibooking',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.merchant,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: _username,
                          enabled: !busy,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: l.username,
                            prefixIcon: const Icon(Icons.person_outline),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? l.enterYourUsername
                                  : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _password,
                          enabled: !busy,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => busy ? null : _submit(),
                          decoration: InputDecoration(
                            labelText: l.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              tooltip:
                                  _obscure ? l.showPassword : l.hidePassword,
                            ),
                          ),
                          validator: (value) => (value == null || value.isEmpty)
                              ? l.enterYourPassword
                              : null,
                        ),
                        if (widget.auth.badCredentials ||
                            widget.auth.throttled ||
                            widget.auth.errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 20,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.auth.throttled
                                        ? l.tooManyAttempts
                                        : widget.auth.badCredentials
                                            ? l.wrongUsernameOrPassword
                                            : widget.auth.errorMessage!,
                                    style: TextStyle(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l.signIn),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
