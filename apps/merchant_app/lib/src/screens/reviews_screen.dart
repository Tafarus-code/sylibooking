import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';
import '../auth_controller.dart';

/// What customers said, for the venue they said it about.
///
/// A merchant who cannot read their reviews here reads them on Facebook
/// instead, where nobody can report anything and the platform hears about a
/// problem last.
///
/// Reporting is all a venue may do, and the screen says so out loud. A venue
/// able to take down its own bad reviews would leave the ratings worth
/// nothing to the customers they exist to inform — so the wording never
/// implies otherwise, and the review stays on screen after it is reported.
class ReviewsScreen extends StatefulWidget {
  const ReviewsScreen({super.key, required this.auth});

  final AuthController auth;

  @override
  State<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends State<ReviewsScreen> {
  MerchantReviewPage? _page;
  bool _loading = true;
  String? _error;
  final Set<int> _busy = {};

  int get _venueId => widget.auth.selectedVenueId!;
  bool get _canReport => widget.auth.role.canEditProfile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.auth.api.merchantReviews(_venueId);
      if (!mounted) return;
      setState(() {
        _page = page;
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

  Future<void> _report(MerchantReview review) async {
    final l = L.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _ReportDialog(review: review),
    );
    if (reason == null || !mounted) return;

    setState(() => _busy.add(review.id));
    try {
      await widget.auth.api.flagReview(
        establishmentId: _venueId,
        reviewId: review.id,
        reason: reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l.reviewReported)));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(e.messageOr(whenThrottled: l.tooManyAttempts)),
          ),
        );
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy.remove(review.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l.reviews)),
      body: RefreshIndicator(onRefresh: _load, child: _body(l)),
    );
  }

  Widget _body(L l) {
    final theme = Theme.of(context);

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32)
            .copyWith(top: 72, bottom: 32),
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: _load, child: Text(l.tryAgain)),
        ],
      );
    }

    final page = _page!;
    if (page.reviews.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: contentInsets(context, minHorizontal: 32)
            .copyWith(top: 72, bottom: 32),
        children: [
          Icon(
            Icons.reviews_outlined,
            size: 56,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            l.noReviewsYet,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l.noReviewsDetail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: contentInsets(context, maxWidth: ContentWidth.list)
          .copyWith(bottom: 32),
      children: [
        _Summary(page: page),
        for (final review in page.reviews)
          _ReviewCard(
            review: review,
            busy: _busy.contains(review.id),
            onReport: _canReport && !review.isFlagged && !review.isHidden
                ? () => _report(review)
                : null,
          ),
      ],
    );
  }
}

/// The average, and the shape behind it.
class _Summary extends StatelessWidget {
  const _Summary({required this.page});

  final MerchantReviewPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);
    // Each bar is that star's share of all the reviews, not its share of the
    // biggest bucket. Scaling to the biggest makes a full bar mean "the most
    // common score" rather than "all of them" — so a venue with three fives
    // and three ones showed two full bars, which reads as everybody loving it
    // and everybody hating it at the same time.
    final total = page.distribution.values.fold(0, (a, b) => a + b);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  page.averageRating == null
                      ? '—'
                      : page.averageRating!.toStringAsFixed(1),
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    l.reviewCount(page.total),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Five to one, because that is the order a merchant scans it in.
            for (final star in [5, 4, 3, 2, 1])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      child: Text(
                        '$star',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Icon(
                      Icons.star,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: total == 0
                              ? 0
                              : (page.distribution[star] ?? 0) / total,
                          minHeight: 6,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${page.distribution[star] ?? 0}',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.busy,
    this.onReport,
  });

  final MerchantReview review;
  final bool busy;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  Icon(
                    star <= review.rating ? Icons.star : Icons.star_border,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    review.authorDisplayName,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  DateFormat.yMMMd(l.localeName).format(review.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.comment),
            ],
            if (review.isHidden) ...[
              const SizedBox(height: 8),
              Text(
                l.reviewTakenDown,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ] else if (review.isFlagged) ...[
              const SizedBox(height: 8),
              Text(
                l.reviewFlagged,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (onReport != null) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: busy ? null : onReport,
                  icon: const Icon(Icons.outlined_flag, size: 18),
                  label: Text(l.reportReview),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Asks for a reason, and says plainly what reporting does and does not do.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.review});

  final MerchantReview review;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = L.of(context).reportReasonRequired);
      return;
    }
    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);

    return AlertDialog(
      title: Text(l.reportReviewTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The expectation set before the tap, not after: this is not a
          // delete button and must never read like one.
          Text(
            l.reportReviewDetail,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l.reportReason,
              hintText: l.reportReasonHint,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.send)),
      ],
    );
  }
}
