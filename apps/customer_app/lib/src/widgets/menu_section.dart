import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

/// The menu, grouped by category, as a card per dish.
///
/// A browsing aid, not an ordering flow: a picture, a name, a price. Renders
/// nothing at all when there is no menu — many pilot merchants will not have
/// filled one in, and an empty heading reads as a broken screen.
class MenuSection extends StatelessWidget {
  const MenuSection({super.key, required this.menu});

  final List<MenuCategory> menu;

  /// Gap between cards, and between the two columns.
  static const _gap = 12.0;

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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              category.categoryDisplay,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Measured rather than assumed: the section is laid out inside
                // the detail screen, whose width this widget does not get to
                // decide — and on a tablet or desktop that is far more than
                // two cards' worth.
                // 160 keeps the phone on two columns, which is the layout the
                // cards were drawn for; wider windows simply fit more of them.
                final columns = columnsForWidth(
                  constraints.maxWidth,
                  targetCardWidth: 160,
                  max: 5,
                );
                final cardWidth =
                    (constraints.maxWidth - _gap * (columns - 1)) / columns;

                // Wrap rather than a grid: a dish with a two-line name makes
                // its own card taller instead of overflowing a fixed cell.
                return Wrap(
                  spacing: _gap,
                  runSpacing: _gap,
                  children: [
                    for (final item in category.items)
                      SizedBox(
                        width: cardWidth,
                        child: MenuItemCard(item: item),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

/// One dish: picture on top, name and price beneath.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({super.key, required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 4 / 3, child: _Picture(item: item)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.price} GNF',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The dish photo, or a placeholder that looks deliberate.
///
/// Most items will have no picture for a while yet: merchants fill the menu in
/// first and photograph it later, if at all.
class _Picture extends StatelessWidget {
  const _Picture({required this.item});

  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = item.imageUrl;

    Widget placeholder(IconData icon) => Container(
          color: theme.colorScheme.secondaryContainer,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 28,
            color: theme.colorScheme.onSecondaryContainer
                .withValues(alpha: 0.55),
          ),
        );

    if (url == null) return placeholder(Icons.restaurant_menu);

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) =>
          placeholder(Icons.broken_image_outlined),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(color: theme.colorScheme.secondaryContainer),
    );
  }
}
