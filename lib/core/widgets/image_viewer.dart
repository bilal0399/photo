import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen, zoomable viewer for an image file. Works on every platform.
/// Pass [heroTag] to animate a thumbnail into the full view.
Future<void> showImageViewer(BuildContext context, String path, {Object? heroTag}) {
  final image = Image.file(
    File(path),
    errorBuilder: (_, _, _) => const Icon(
      Icons.broken_image_outlined,
      color: Colors.white54,
      size: 80,
    ),
  );
  return _viewer(context, image, heroTag);
}

/// Full-screen viewer for a network image (Supabase signed URL).
/// Pass the storage path as [cacheKey] so the thumbnail's cached copy is reused.
Future<void> showNetworkImageViewer(
  BuildContext context,
  String url, {
  Object? heroTag,
  String? cacheKey,
}) {
  final image = CachedNetworkImage(
    imageUrl: url,
    cacheKey: cacheKey,
    fit: BoxFit.contain,
    placeholder: (_, _) => const CircularProgressIndicator(color: Colors.white54),
    errorWidget: (_, _, _) =>
        const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 80),
  );
  return _viewer(context, image, heroTag);
}

Future<void> _viewer(BuildContext context, Widget image, Object? heroTag) {
  return showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.9),
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: heroTag != null ? Hero(tag: heroTag, child: image) : image,
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}
