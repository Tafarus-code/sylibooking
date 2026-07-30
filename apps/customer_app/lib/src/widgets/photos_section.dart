import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

/// A horizontal strip of photos of the venue.
///
/// Renders nothing when there are none — a venue that has uploaded nothing
/// should not show an empty band where pictures ought to be.
class PhotosSection extends StatelessWidget {
  const PhotosSection({
    super.key,
    required this.photos,
    required this.loading,
    this.onTapPhoto,
  });

  final List<Photo> photos;
  final bool loading;
  final void Function(Photo photo)? onTapPhoto;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (photos.isEmpty) return const SizedBox.shrink();

    // A grid, not a carousel. Sideways scrolling hid most of a venue's
    // pictures behind a gesture nobody makes, and the page already scrolls
    // downwards — so the photos go the same way as the menu cards.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 8.0;
          // 160 keeps a phone on two columns; wider windows fit more.
          final columns = columnsForWidth(
            constraints.maxWidth,
            targetCardWidth: 160,
            max: 5,
          );
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final photo in photos)
                SizedBox(
                  width: width,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: _PhotoThumb(
                      photo: photo,
                      onTap:
                          onTapPhoto == null ? null : () => onTapPhoto!(photo),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, this.onTap});

  final Photo photo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                photo.imageUrl,
                fit: BoxFit.cover,
                // A photo that will not load must not blow up the strip.
                errorBuilder: (context, _, _) => Container(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                      ),
              ),
              if (photo.caption.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    // Not themed on purpose: a caption sits on an arbitrary
                    // photograph, where only a dark scrim with light text can
                    // be relied on to stay readable.
                    color: Colors.black54,
                    child: Text(
                      photo.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
