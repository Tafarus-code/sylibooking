import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';

/// Pick the venue's look from a curated set.
///
/// Five presets, no colour picker and no font picker. Every one has been
/// checked for contrast, so whatever a merchant chooses stays readable — which
/// a free-form picker could not promise.
class BrandingScreen extends StatefulWidget {
  const BrandingScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  late String _selected = defaultThemePresetKey;
  String? _saved;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  int get _venueId => widget.auth.selectedVenueId!;
  String get _venueName => widget.auth.selectedVenue?.name ?? 'Your venue';

  bool get _dirty => _selected != _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final venue = await widget.auth.api.merchantProfile(_venueId);
      if (!mounted) return;
      setState(() {
        _selected = venue.themePreset;
        _saved = venue.themePreset;
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The same ownership-checked profile endpoint as every other field.
      await widget.auth.api.updateProfile(_venueId, {
        'theme_preset': _selected,
      });
      if (!mounted) return;
      setState(() {
        _saved = _selected;
        _saving = false;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Branding saved.')));
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
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Branding')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              key: const Key('branding-list'),
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    'Choose how $_venueName looks to customers. Each set has '
                    'been checked for readability.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                for (final preset in themePresets)
                  _PresetCard(
                    preset: preset,
                    venueName: _venueName,
                    selected: preset.key == _selected,
                    onTap: _saving
                        ? null
                        : () => setState(() => _selected = preset.key),
                  ),

                const SizedBox(height: 8),
                _SectionLabel('Preview'),
                // The selection applied to a miniature of the customer's
                // detail screen, before it is saved.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: EstablishmentThemeScope(
                    presetKey: _selected,
                    child: Builder(
                      builder: (context) => _Preview(venueName: _venueName),
                    ),
                  ),
                ),

                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: (_saving || !_dirty) ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_dirty ? 'Save branding' : 'Saved'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// One swatch: the accent, and the venue's own name in the display face.
class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.venueName,
    required this.selected,
    this.onTap,
  });

  final ThemePreset preset;
  final String venueName;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? preset.accent : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // The accent itself, with the venue's name set in the preset's
              // display face on top of it — the actual pairing, not a label.
              Container(
                width: 96,
                height: 64,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: preset.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  venueName,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: preset.onAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.name, style: theme.textTheme.titleMedium),
                    Text(
                      preset.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${preset.displayFont} · ${preset.bodyFont}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: preset.accent)
              else
                const Icon(Icons.circle_outlined),
            ],
          ),
        ),
      ),
    );
  }
}

/// A miniature of what a customer sees, under the chosen preset.
class _Preview extends StatelessWidget {
  const _Preview({required this.venueName});

  final String venueName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: Text(
              venueName,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Open until 02:00', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Lounge · Conakry · 1.2 km away',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final time in ['19:00', '20:30', '22:00'])
                      Chip(
                        label: Text(time),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: null,
                  child: const Text('Reserve'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
