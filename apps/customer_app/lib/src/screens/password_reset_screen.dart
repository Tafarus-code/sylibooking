import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_client/shared_client.dart';

/// Forgot the password: ask for a code, then use it.
///
/// One screen in two states rather than two screens, so the identifier the
/// customer typed stays on screen while they read the code off their phone.
class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    required this.api,
    this.initialIdentifier = '',
  });

  final SylibookingApi api;

  /// Whatever they had already typed into the sign-in form.
  final String initialIdentifier;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _identifier =
      TextEditingController(text: widget.initialIdentifier);
  final _code = TextEditingController();
  final _password = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;
  String? _sentTo;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_identifier.text.trim().isEmpty) {
      setState(() => _error = 'Enter your username, phone or email.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result =
          await widget.api.requestPasswordReset(_identifier.text.trim());
      if (!mounted) return;
      setState(() {
        // Move on whatever the server said: it answers the same way for an
        // account that does not exist, and the app must not leak the
        // difference by behaving differently.
        _codeSent = true;
        _sentTo = result.sentTo;
        _busy = false;
      });
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } on ApiUnreachableException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final message = await widget.api.confirmPasswordReset(
        identifier: _identifier.text.trim(),
        code: _code.text.trim(),
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(message);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    } on ApiUnreachableException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Forgotten password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: contentInsets(context, vertical: 24, minHorizontal: 24),
          children: [
            Text(
              _codeSent ? 'Enter the code' : 'Get a code',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _codeSent
                  ? 'We sent a six digit code to ${_sentTo ?? "you"}. It is '
                      'good for 15 minutes.'
                  : 'Tell us your username, phone number or email and we will '
                      'send a code to whichever we have on file.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _identifier,
              enabled: !_codeSent,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Username, phone or email',
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _code,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(labelText: 'Six digit code'),
                validator: (value) => (value ?? '').trim().length < 6
                    ? 'The code is six digits.'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (value) => (value ?? '').length < 8
                    ? 'At least 8 characters.'
                    : null,
              ),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : (_codeSent ? _confirm : _request),
              child: Text(
                _busy
                    ? 'Just a moment…'
                    : _codeSent
                        ? 'Change my password'
                        : 'Send me a code',
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : _request,
                child: const Text('Send another code'),
              ),
              const SizedBox(height: 4),
              Text(
                'Asking for a new code cancels the last one.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
