import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';

/// English or French, from the Manage screen.
///
/// Each language is written in its own language — "Français", not "French" —
/// because the person who needs this control is the one who cannot read the
/// language currently on screen.
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key, required this.controller});

  final LocaleController controller;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.effective(context).languageCode;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.language, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'en',
                    label: Text(
                      l.languageEnglish,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                  ButtonSegment(
                    value: 'fr',
                    label: Text(
                      l.languageFrench,
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ],
                selected: {current == 'fr' ? 'fr' : 'en'},
                onSelectionChanged: (selection) =>
                    controller.set(Locale(selection.first)),
              ),
            ],
          ),
        );
      },
    );
  }
}
