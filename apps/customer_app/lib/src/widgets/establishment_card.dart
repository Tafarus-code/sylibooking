import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';

/// One venue on the browse list.
///
/// Cover photo carrying two badges — status top-left, distance bottom-right —
/// with the name in the display face beneath and the rating line under that.
///
/// Chrome, not venue branding: this reads the app theme even when the venue
/// has its own preset. A list where every card looked different would be
/// unreadable.
class EstablishmentCard extends StatelessWidget {
  const EstablishmentCard({
    super.key,
    required this.establishment,
    required this.onTap,
    this.coverUrl,
    this.distanceKm,
    this.isFavourite = false,
    this.onToggleFavourite,
  });

  final Establishment establishment;
  final VoidCallback onTap;

  /// Saved on this device. Null callback means the heart is not offered at
  /// all, which is how the card renders anywhere favouriting makes no sense.
  final bool isFavourite;
  final VoidCallback? onToggleFavourite;

  /// First photo, when the venue has one.
  final String? coverUrl;

  /// Null without a location fix, or when the venue has no coordinates.
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cover = Stack(
      fit: StackFit.expand,
      children: [
        _Cover(establishment: establishment, coverUrl: coverUrl),
        Positioned(
          top: 10,
          left: 10,
          child: _StatusBadge(establishment: establishment),
        ),
        if (distanceKm case final km?)
          Positioned(
            bottom: 10,
            right: 10,
            child: _Badge(label: formatDistance(km), icon: Icons.near_me),
          ),
        if (onToggleFavourite case final toggle?)
          Positioned(
            top: 4,
            right: 4,
            child: _HeartButton(saved: isFavourite, onPressed: toggle),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // In a list the card is free to be as tall as its cover needs;
                // in a grid cell the height is already decided, so the cover
                // takes what is left after the text rather than overflowing it.
                if (constraints.hasBoundedHeight)
                  Expanded(child: cover)
                else
                  AspectRatio(aspectRatio: 16 / 9, child: cover),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        establishment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // Display face: the one piece of type that carries the
                        // house voice on this screen.
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _RatingLine(establishment: establishment),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.establishment, this.coverUrl});

  final Establishment establishment;
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = coverUrl;

    if (url == null) {
      // Most venues start with no photos, so the placeholder has to look
      // deliberate rather than broken.
      return Container(
        color: theme.colorScheme.secondaryContainer,
        alignment: Alignment.center,
        child: Icon(
          establishment.type == EstablishmentType.lounge
              ? Icons.local_fire_department
              : Icons.restaurant,
          size: 40,
          color: theme.colorScheme.onSecondaryContainer.withValues(alpha: 0.55),
        ),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) => Container(
        color: theme.colorScheme.secondaryContainer,
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(color: theme.colorScheme.secondaryContainer),
    );
  }
}

/// A dot plus a word: colour alone would exclude anyone who cannot see it.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.establishment});

  final Establishment establishment;

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    // Nothing recorded is not the same as shut; saying "Closed" would be a
    // guess, and pilot merchants will not all have filled their hours in.
    final unknown = establishment.today == null && !establishment.hasHours;

    if (unknown) {
      return _Badge(
        label: l.statusHoursNotListed,
        dotColour: const Color(0xFF9AA0A6),
      );
    }

    final open = establishment.isOpenNow;
    return _Badge(
      // "Open until 02:00" rather than the mockup's bare "Open": for a lounge
      // at 23:00 the closing time is the thing the customer is actually asking,
      // and it fits the badge on a 360dp phone.
      label: open
          ? l.statusOpenUntil(establishment.closesAtDisplay)
          : l.statusClosed,
      dotColour: open
          ? const Color(0xFF3FBF7F)
          : theme.colorScheme.error,
    );
  }
}

/// Save this venue for later, from the list.
///
/// Fixed white on a dark scrim, like the badges: it sits on an arbitrary
/// photograph and has to stay visible whatever is behind it.
class _HeartButton extends StatelessWidget {
  const _HeartButton({required this.saved, required this.onPressed});

  final bool saved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(saved ? Icons.favorite : Icons.favorite_border),
        color: Colors.white,
        // Both states named: "Saved" alone would leave a screen reader unable
        // to tell what the tap will do.
        tooltip: saved
            ? L.of(context).removeFromFavourites
            : L.of(context).saveToFavourites,
        style: IconButton.styleFrom(backgroundColor: const Color(0x6610231B)),
        onPressed: onPressed,
      );
}

/// Legible over any photo: dark scrim, light text, fixed regardless of theme.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.dotColour, this.icon});

  final String label;
  final Color? dotColour;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        // Deliberately not themed: it sits on an arbitrary photograph, where
        // only a dark scrim guarantees the text can be read.
        color: const Color(0xCC10231B),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColour != null)
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColour,
                shape: BoxShape.circle,
              ),
            ),
          if (icon != null) Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.establishment});

  final Establishment establishment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Row(
      children: [
        if (establishment.averageRating case final rating?) ...[
          Icon(Icons.star, size: 16, color: theme.colorScheme.tertiary),
          const SizedBox(width: 3),
          Text(rating.toStringAsFixed(1), style: muted),
          Text('  ·  ', style: muted),
        ],
        Flexible(
          child: Text(
            '${establishment.typeDisplay} · ${establishment.city}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: muted,
          ),
        ),
      ],
    );
  }
}
