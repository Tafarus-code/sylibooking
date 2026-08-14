import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';

/// The venue's own details. Owner and manager only.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  int get _venueId => widget.auth.selectedVenueId!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _tagline.dispose();
    _description.dispose();
    _address.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final venue = await widget.auth.api.merchantProfile(_venueId);
      if (!mounted) return;
      setState(() {
        _name.text = venue.name;
        _tagline.text = venue.tagline;
        _description.text = venue.description;
        _address.text = venue.address;
        _city.text = venue.city;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l = L.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.auth.api.updateProfile(_venueId, {
        'name': _name.text.trim(),
        'tagline': _tagline.text.trim(),
        'description': _description.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.detailsSaved)));
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

    return Scaffold(
      appBar: AppBar(title: Text(l.venueDetails)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _field(_name, l.fieldName, required: true),
                  _field(_tagline, l.fieldTagline),
                  _field(_description, l.fieldDescription, maxLines: 4),
                  _field(_city, l.fieldCity, required: true),
                  _field(_address, l.fieldAddress, maxLines: 2, required: true),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l.save),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          enabled: !_saving,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          validator: required
              ? (value) => (value == null || value.trim().isEmpty)
                  ? L.of(context).required
                  : null
              : null,
        ),
      );
}
