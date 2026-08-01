import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import 'rating_stars.dart';

/// What other guests thought.
///
/// Shows the average and the most recent handful; the full list is a tap
/// away. A venue nobody has reviewed says so plainly rather than showing an
/// empty heading — most pilot venues will start here.
class ReviewsSection extends StatelessWidget {
  const ReviewsSection({
    super.key,
    required this.establishment,
    required this.reviews,
    required this.loading,
    this.onSeeAll,
    this.previewCount = 3,
  });

  final Establishment establishment;
  final List<Review> reviews;
  final bool loading;
  final VoidCallback? onSeeAll;
  final int previewCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = reviews.take(previewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Text(
                L.of(context).reviews,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (reviews.length > previewCount && onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: Text(L.of(context).seeAllReviews(establishment.reviewCount)),
                ),
            ],
          ),
        ),
        if (establishment.averageRating case final average?)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                RatingStars(rating: average, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${establishment.reviewCount} '
                  '${establishment.reviewCount == 1 ? "review" : "reviews"}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              L.of(context).noReviewsAfterVisit,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final review in preview) ReviewTile(review: review),
      ],
    );
  }
}

class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RatingStars(
                rating: review.rating.toDouble(),
                size: 14,
                showNumber: false,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.author,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                DateFormat.yMMMd().format(review.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (review.comment.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(review.comment, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}
