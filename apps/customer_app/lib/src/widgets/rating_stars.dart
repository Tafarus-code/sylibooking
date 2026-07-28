import 'package:flutter/material.dart';

/// A 1-5 rating, read-only.
///
/// Always paired with the number: stars alone are hard to count at a glance
/// and carry nothing for a screen reader.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 16,
    this.showNumber = true,
  });

  final double rating;
  final double size;
  final bool showNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rounded = rating.round();

    return Semantics(
      label: '${rating.toStringAsFixed(1)} out of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var star = 1; star <= 5; star++)
            Icon(
              star <= rounded ? Icons.star : Icons.star_border,
              size: size,
              color: theme.colorScheme.tertiary,
            ),
          if (showNumber) ...[
            const SizedBox(width: 6),
            Text(
              rating.toStringAsFixed(1),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A tappable 1-5 picker for leaving a review.
class RatingPicker extends StatelessWidget {
  const RatingPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = 1; star <= 5; star++)
          IconButton(
            onPressed: enabled ? () => onChanged(star) : null,
            iconSize: 40,
            tooltip: '$star ${star == 1 ? "star" : "stars"}',
            icon: Icon(
              star <= value ? Icons.star : Icons.star_border,
              color: theme.colorScheme.tertiary,
            ),
          ),
      ],
    );
  }
}
