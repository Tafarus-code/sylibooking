import 'package:flutter/material.dart';

import '../customer_auth.dart';
import 'password_reset_screen.dart';

/// The account, if there is one.
///
/// Signed out this screen is an offer, not a wall: everything in the app
/// already works, and the copy says exactly what signing up would add rather
/// than implying anything is being withheld.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.auth});

  final CustomerAuth auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => auth.isSignedIn
            ? _SignedIn(auth: auth)
            : _SignedOut(auth: auth),
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.auth});

  final CustomerAuth auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final customer = auth.customer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 96),
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            (customer?.firstName ?? '?').characters.first.toUpperCase(),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          customer?.name ?? '',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        Text(
          '@${customer?.username ?? ''}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.cloud_done_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your bookings, orders and favourites are saved to this '
                    'account. Sign in on another phone and they follow you.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: auth.signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 8),
        Text(
          'Signing out leaves this phone with what it had before — nothing '
          'is deleted.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SignedOut extends StatefulWidget {
  const _SignedOut({required this.auth});

  final CustomerAuth auth;

  @override
  State<_SignedOut> createState() => _SignedOutState();
}

class _SignedOutState extends State<_SignedOut> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  /// Registering by default: someone arriving here has no account, or they
  /// would already be signed in on this phone.
  bool _registering = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _forgotten() async {
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PasswordResetScreen(
          api: widget.auth.api,
          initialIdentifier: _usernameController.text.trim(),
        ),
      ),
    );
    if (message != null && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final ok = _registering
        ? await widget.auth.register(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            name: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
          )
        : await widget.auth.signIn(
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );

    if (ok && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Signed in. Everything on this phone is saved.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = widget.auth;

    return Form(
      key: _formKey,
      child: ListView(
        // Generous at the bottom: the last controls are buttons, and on a
        // 360dp phone they otherwise finish underneath the navigation bar.
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        children: [
          Icon(
            Icons.person_outline,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            _registering ? 'Make an account' : 'Welcome back',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'You do not need one. Everything works without it — an account '
            'just keeps your bookings and favourites if you change phone.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (_registering) ...[
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Your name'),
              textInputAction: TextInputAction.next,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? 'What should we call you?'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                helperText: 'So you can get back in if you forget the password',
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (value) {
                // Not required — an account with no contact is allowed, and
                // the app says what that costs rather than refusing it.
                final phone = (value ?? '').trim();
                if (phone.isEmpty) return null;
                return phone.length < 8 ? 'That number looks too short.' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email (optional)',
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) return null;
                return email.contains('@') ? null : 'That email looks wrong.';
              },
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? 'Pick a username.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: const InputDecoration(labelText: 'Password'),
            obscureText: true,
            validator: (value) {
              final password = value ?? '';
              if (password.isEmpty) return 'Enter a password.';
              if (_registering && password.length < 8) {
                return 'At least 8 characters.';
              }
              return null;
            },
          ),
          if (auth.error case final error?) ...[
            const SizedBox(height: 16),
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: auth.busy ? null : _submit,
            child: Text(
              auth.busy
                  ? 'Just a moment…'
                  : _registering
                      ? 'Create account'
                      : 'Sign in',
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: auth.busy
                ? null
                : () => setState(() => _registering = !_registering),
            child: Text(
              _registering
                  ? 'I already have an account'
                  : 'I need an account',
            ),
          ),
          if (!_registering)
            TextButton(
              onPressed: auth.busy ? null : _forgotten,
              child: const Text('I have forgotten my password'),
            ),
        ],
      ),
    );
  }
}
