import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_client/shared_client.dart';

import '../../l10n/app_localizations.dart';

/// One venue photo at full size, with the rest of the album a step away.
///
/// Deliberately dark rather than themed: a photograph is judged against black,
/// and an ivory surround casts its own colour over what the customer came to
/// look at.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.photos,
    required this.initialIndex,
  });

  final List<Photo> photos;
  final int initialIndex;

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index < widget.photos.length - 1;

  void _go(int delta) {
    final target = _index + delta;
    if (target < 0 || target >= widget.photos.length) return;
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Arrow keys and Escape, for anyone on a keyboard.
  ///
  /// Swiping is the obvious gesture on a phone and impossible everywhere else,
  /// which is the whole reason the on-screen arrows exist too.
  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        _go(-1);
      case LogicalKeyboardKey.arrowRight:
        _go(1);
      case LogicalKeyboardKey.escape:
        Navigator.of(context).pop();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l = L.of(context);
    final photo = widget.photos[_index];

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _onKey(event),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l.backToPhotos,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l.photoOf(_index + 1, widget.photos.length),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        body: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              onPageChanged: (index) => setState(() => _index = index),
              itemCount: widget.photos.length,
              itemBuilder: (context, index) => _Page(photo: widget.photos[index]),
            ),
            // Arrows on both sides: a mouse cannot swipe, and on a wide window
            // the edges are where the pointer already is.
            if (_hasPrevious)
              _ArrowButton(
                alignment: Alignment.centerLeft,
                icon: Icons.chevron_left,
                tooltip: l.previousPhoto,
                onPressed: () => _go(-1),
              ),
            if (_hasNext)
              _ArrowButton(
                alignment: Alignment.centerRight,
                icon: Icons.chevron_right,
                tooltip: l.nextPhoto,
                onPressed: () => _go(1),
              ),
            if (photo.caption.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _Caption(text: photo.caption),
              ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      // Pinch or scroll to zoom, which is the point of full screen.
      minScale: 1,
      maxScale: 4,
      // Expand rather than Center: a Center hands the image loose constraints,
      // so BoxFit.contain has nothing to fit into and a small picture renders
      // at its natural size in the middle of a black screen. Filling the space
      // lets contain scale it up to the window, aspect intact.
      child: SizedBox.expand(
        child: Image.network(
          photo.imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, _, _) => const _Unavailable(),
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              L.of(context).photoCouldNotLoad,
              style: const TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: IconButton(
              icon: Icon(icon, color: Colors.white),
              tooltip: tooltip,
              onPressed: onPressed,
            ),
          ),
        ),
      );
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      );
}
