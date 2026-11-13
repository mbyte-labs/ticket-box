import 'package:freezed_annotation/freezed_annotation.dart';

part 'details_watch_provider.freezed.dart';

/// One logo of the *Watch now* row on the details pages: a streaming service carrying the title
/// in the user's country. [logoUrl] is already a full TMDB image URL; null renders the fallback
/// tile.
@freezed
abstract class DetailsWatchProvider with _$DetailsWatchProvider {
  const factory DetailsWatchProvider({required String name, String? logoUrl}) = _DetailsWatchProvider;
}
