import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';

import '../widgets/rating_stars.dart';

/// Leave a review for a visit that happened.
///
/// The reservation reference is the credential — the server checks the visit
/// is complete, at this venue, and not already reviewed, so this screen's job
/// is to collect a rating and relay whatever the server says.
class WriteReviewScreen extends StatefulWidget {
  const WriteReviewScreen({
    super.key,
    required this.api,
    required this.reservation,
  });

  final SylibookingApi api;
  final Reservation reservation;

  @override
  State<WriteReviewScreen> createState() => _WriteReviewScreenState();
}

class _WriteReviewScreenState extends State<WriteReviewScreen> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = L.of(context).chooseARating);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await widget.api.createReview(
        establishmentId: widget.reservation.establishmentId!,
        reservationReference: widget.reservation.reference,
        rating: _rating,
        comment: _comment.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    } on ApiUnreachableException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final theme = Theme.of(context);
    final reservation = widget.reservation;

    return Scaffold(
      appBar: AppBar(title: Text(l.writeAReview)),
      body: ListView(
        padding: contentInsets(context, vertical: 16, minHorizontal: 16),
        children: [
          Text(
            reservation.establishmentName,
            style: theme.textTheme.titleMedium,
          ),
          Text(
            '${DateFormat.yMMMEd().format(reservation.dateTime)} · '
            '${reservation.spaceName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            l.howWasIt,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          RatingPicker(
            value: _rating,
            enabled: !_submitting,
            onChanged: (value) => setState(() {
              _rating = value;
              _error = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            enabled: !_submitting,
            maxLines: 4,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.anythingToAdd,
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 20,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.postReview),
          ),
          const SizedBox(height: 8),
          Text(
            l.onlyFirstNameShown,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
