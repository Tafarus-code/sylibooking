import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';
import 'spaces_screen.dart';

/// A merchant registering their own venue.
///
/// Four fields and no more. Tagline, description, hours, menu, photos and
/// branding all have their own screens the moment the venue exists, and a
/// wall of fields between a merchant and their first venue is the surest way
/// to lose them at the only step that has no reward yet.
///
/// On success this lands on the seating plan rather than the desk: a venue
/// with no tables cannot take a booking, and the spaces screen's empty state
/// already says so.
class CreateVenueScreen extends StatefulWidget {
  const CreateVenueScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<CreateVenueScreen> createState() => _CreateVenueScreenState();
}

class _CreateVenueScreenState extends State<CreateVenueScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  String _type = 'restaurant';

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l = L.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final venue = await widget.auth.api.createEstablishment(
        name: _name.text.trim(),
        type: _type,
        city: _city.text.trim(),
        address: _address.text.trim(),
      );
      // Switch to it before leaving, so the screen underneath is already the
      // new venue's rather than the empty state that sent us here.
      final adopted = await widget.auth.adoptVenue(venue.id);
      if (!mounted) return;

      messenger
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.venueCreated(venue.name))));

      // Only walk on to the seating plan if there is genuinely a venue
      // selected to lay out. If the reload did not bring it back — a flaky
      // network, a slow replica — the venue still exists and the list will
      // catch up; stepping into a screen that assumes a selection would
      // crash on the way in.
      if (adopted) {
        navigator.pushReplacement(
          MaterialPageRoute(
            builder: (_) => SpacesScreen(auth: widget.auth),
          ),
        );
      } else {
        navigator.pop();
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.createVenue)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: contentInsets(context, vertical: 16, minHorizontal: 16),
          children: [
            Text(
              l.createVenueIntro,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.fieldName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? l.required : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(
                labelText: l.venueKind,
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'restaurant',
                  child: Text(l.venueKindRestaurant),
                ),
                DropdownMenuItem(
                  value: 'lounge',
                  child: Text(l.venueKindLounge),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _type = value ?? 'restaurant'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _city,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: l.fieldCity,
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? l.required : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              enabled: !_saving,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: l.fieldAddress,
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? l.required : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l.createVenueCta),
            ),
          ],
        ),
      ),
    );
  }
}
