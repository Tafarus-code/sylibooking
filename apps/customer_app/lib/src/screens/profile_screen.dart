import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

import '../customer_auth.dart';
import 'package:shared_client/shared_client.dart';
import '../widgets/language_toggle.dart';
import 'password_reset_screen.dart';

/// The account, if there is one.
///
/// Signed out this screen is an offer, not a wall: everything in the app
/// already works, and the copy says exactly what signing up would add rather
/// than implying anything is being withheld.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.auth,
    required this.localeController,
  });

  final CustomerAuth auth;
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.of(context).profile)),
      body: ListenableBuilder(
        listenable: auth,
        builder: (context, _) => auth.isSignedIn
            ? _SignedIn(auth: auth, localeController: localeController)
            : _SignedOut(auth: auth, localeController: localeController),
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({required this.auth, required this.localeController});

  final CustomerAuth auth;
  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
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
                    l.accountKeepsEverything,
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
          label: Text(l.signOut),
        ),
        const SizedBox(height: 8),
        Text(
          l.signOutKeepsPhone,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
        LanguageToggle(controller: localeController),
      ],
    );
  }
}

class _SignedOut extends StatefulWidget {
  const _SignedOut({required this.auth, required this.localeController});

  final CustomerAuth auth;
  final LocaleController localeController;

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
          SnackBar(content: Text(L.of(context).signedInEverythingSaved)),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
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
            _registering ? l.makeAnAccount : l.welcomeBack,
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
              decoration: InputDecoration(labelText: l.yourName),
              textInputAction: TextInputAction.next,
              validator: (value) => (value ?? '').trim().isEmpty
                  ? l.whatShouldWeCallYou
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: InputDecoration(
                labelText: l.phoneNumber,
                helperText: l.phoneHelper,
              ),
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (value) {
                // Not required — an account with no contact is allowed, and
                // the app says what that costs rather than refusing it.
                final phone = (value ?? '').trim();
                if (phone.isEmpty) return null;
                return phone.length < 8 ? l.phoneTooShort : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: InputDecoration(labelText: l.emailOptional),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) return null;
                return email.contains('@') ? null : l.emailLooksWrong;
              },
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(labelText: l.username),
            textInputAction: TextInputAction.next,
            autocorrect: false,
            validator: (value) =>
                (value ?? '').trim().isEmpty ? l.pickAUsername : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(labelText: l.password),
            obscureText: true,
            validator: (value) {
              final password = value ?? '';
              if (password.isEmpty) return l.enterAPassword;
              if (_registering && password.length < 8) {
                return l.atLeast8Characters;
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
              child: Text(l.iForgotMyPassword),
            ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          // Offered signed out as well as signed in. Someone who cannot read
          // the app is exactly the person who has not made an account yet,
          // and making them sign up first to change the language would be
          // the wrong way round.
          LanguageToggle(controller: widget.localeController),
        ],
      ),
    );
  }
}
