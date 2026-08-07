import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';

/// Dishes across every venue, two to a row.
///
/// The other half of discovery. Browsing by venue asks "where shall we go"
/// and answers with names; this asks "what do I feel like" and answers with
/// food — which is the question somebody scrolling at seven in the evening is
/// actually asking. Tapping a dish opens its venue, so the two halves meet.
///
/// Two columns rather than one: a dish is a photo and three short lines, and
/// a full-width card for that much content leaves the screen mostly empty.
class FeaturedGrid extends StatelessWidget {
  const FeaturedGrid({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<FeaturedItem> items;
  final void Function(FeaturedItem item) onTap;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          Icon(
            Icons.restaurant_menu,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            l.noFeaturedDishes,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            l.noFeaturedDishesDetail,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Photo plus three lines. The text half is sized for the worst
        // case — a dish name that wraps onto a second line — because a card
        // that fits "Yassa" and overflows "Thiéboudienne au poisson frais"
        // fails on exactly the names worth featuring.
        childAspectRatio: 0.66,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => _DishCard(
        item: items[index],
        onTap: () => onTap(items[index]),
      ),
    );
  }
}

class _DishCard extends StatelessWidget {
  const _DishCard({required this.item, required this.onTap});

  final FeaturedItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: SizedBox(
                width: double.infinity,
                child: item.imageUrl == null
                    ? const _NoPhoto()
                    : Image.network(
                        item.imageUrl!,
                        fit: BoxFit.cover,
                        // Most items have no photo and some URLs will be
                        // stale; a broken image must not take the card down.
                        errorBuilder: (_, _, _) => const _NoPhoto(),
                      ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.establishmentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      L.of(context).priceWithCurrency(item.price),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sylibookingPriceStyle(context, fontSize: 12)
                          .copyWith(color: const Color(0xFF1F4A34)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoPhoto extends StatelessWidget {
  const _NoPhoto();

  @override
  Widget build(BuildContext context) {
    // A flat wash rather than a broken-image glyph: most dishes will never
    // have a photo, and an error icon on the common case reads as a fault.
    return Container(
      color: const Color(0xFF1F4A34),
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant,
        color: Color(0x66F7F1E4),
        size: 28,
      ),
    );
  }
}
