import 'package:flutter/material.dart';
import 'package:shared_client/shared_client.dart';

import '../auth_controller.dart';
import '../image_source.dart';

/// The venue's own photos.
///
/// Uploading is profile work, so owners and managers only. Everyone can look —
/// staff seeing what customers see is harmless and occasionally useful.
class PhotosScreen extends StatefulWidget {
  const PhotosScreen({
    super.key,
    required this.auth,
    required this.imageSource,
  });

  final AuthController auth;
  final ImageSource imageSource;

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  List<Photo> _photos = const [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  bool get _canUpload => widget.auth.role.canEditProfile;
  int get _venueId => widget.auth.selectedVenueId!;

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
      final page = await widget.auth.api.photos(_venueId);
      if (!mounted) return;
      setState(() {
        _photos = page.results;
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

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  Future<void> _upload({required bool fromCamera}) async {
    final picked = await widget.imageSource.pick(fromCamera: fromCamera);
    // Backing out of the picker is not an error.
    if (picked == null) return;

    final caption = await _askForCaption();
    if (caption == null) return;

    setState(() => _uploading = true);
    try {
      await widget.auth.api.uploadPhoto(
        establishmentId: _venueId,
        bytes: picked.bytes,
        filename: picked.filename,
        caption: caption,
      );
      _notify('Photo added.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } on ApiUnreachableException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<String?> _askForCaption() {
    final caption = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a caption'),
        content: TextField(
          controller: caption,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Optional, e.g. "The terrace at night"',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, caption.text.trim()),
            child: const Text('Upload'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Photos')),
      floatingActionButton: _canUpload
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'camera',
                  onPressed:
                      _uploading ? null : () => _upload(fromCamera: true),
                  tooltip: 'Take a photo',
                  child: const Icon(Icons.photo_camera),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.extended(
                  heroTag: 'gallery',
                  onPressed:
                      _uploading ? null : () => _upload(fromCamera: false),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Add photo'),
                ),
              ],
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Try again'),
                        ),
                      ],
                    )
                  : _photos.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(32, 72, 32, 32),
                          children: [
                            Icon(
                              Icons.photo_library_outlined,
                              size: 56,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No photos yet',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _canUpload
                                  ? 'Customers browse with their eyes. A few '
                                      'good photos of the room go a long way.'
                                  : 'An owner or manager adds photos here.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      : GridView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _photos.length,
                          itemBuilder: (context, index) =>
                              _PhotoTile(photo: _photos[index]),
                        ),
            ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            photo.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, _, _) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                photo.caption.isEmpty
                    ? photo.uploadedByRoleDisplay
                    : photo.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
