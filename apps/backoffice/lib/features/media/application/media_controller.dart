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

final mediaSignedUrlProvider =
    FutureProvider.family<String, Media>((ref, media) {
  return ref.watch(mediaRepositoryProvider).signedUrl(media);
});
