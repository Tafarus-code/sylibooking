import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

/// The menu, grouped by category.
///
/// A browsing aid, not an ordering flow: name, one line of description, price.
/// Renders nothing at all when there is no menu — many pilot merchants will
/// not have filled one in, and an empty heading reads as a broken screen.
class MenuSection extends StatelessWidget {
  const MenuSection({super.key, required this.menu});

  final List<MenuCategory> menu;

  @override
  Widget build(BuildContext context) {
    if (menu.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Menu',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        for (final category in menu) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              category.categoryDisplay,
              style: theme.textTheme.titleSmall,
            ),
          ),
          for (final item in category.items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name, style: theme.textTheme.bodyLarge),
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${item.price} GNF',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
