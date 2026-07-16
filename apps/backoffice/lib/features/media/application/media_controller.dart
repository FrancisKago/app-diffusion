import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared/shared.dart';

import '../../auth/application/auth_controller.dart';
import '../data/media_repository.dart';

final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepository(ref.watch(supabaseClientProvider));
});

final mediaListProvider = FutureProvider<List<Media>>((ref) {
  return ref.watch(mediaRepositoryProvider).list();
});

/// Media enriched with playlist-usage info, most recent first.
final mediaWithUsageListProvider =
    FutureProvider<List<MediaWithUsage>>((ref) {
  return ref.watch(mediaRepositoryProvider).listWithUsage();
});

/// Whether the media library is filtered to unused (obsolete) media only.
final mediaUnusedOnlyFilterProvider = StateProvider<bool>((ref) => false);

final mediaSignedUrlProvider =
    FutureProvider.family<String, Media>((ref, media) {
  return ref.watch(mediaRepositoryProvider).signedUrl(media);
});
