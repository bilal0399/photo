import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service/tasks_service.dart';

/// Shows a task attachment stored in Supabase Storage: resolves a signed URL
/// (cached) then renders it with on-disk image caching for offline reuse.
class TaskImage extends ConsumerWidget {
  const TaskImage({super.key, required this.path, this.fit = BoxFit.cover});

  final String path;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    Widget placeholder(IconData icon) => Center(
          child: Icon(icon, color: theme.hintColor, size: 32),
        );

    if (path.isEmpty) return placeholder(Icons.image_outlined);

    return ref.watch(taskAttachmentUrlProvider(path)).when(
          loading: () => const Center(
            child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, _) => placeholder(Icons.broken_image_outlined),
          data: (url) => url == null
              ? placeholder(Icons.broken_image_outlined)
              : CachedNetworkImage(
                  imageUrl: url,
                  // Signed URLs change on every refresh; the path keeps the
                  // on-disk copy valid across them.
                  cacheKey: path,
                  fit: fit,
                  width: double.infinity,
                  placeholder: (_, _) => const Center(
                    child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, _, _) => placeholder(Icons.broken_image_outlined),
                ),
        );
  }
}
