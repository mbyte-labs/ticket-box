import 'package:freezed_annotation/freezed_annotation.dart';

part 'model.freezed.dart';
part 'model.g.dart';

@freezed
abstract class TmdbAvailableProviderRegion with _$TmdbAvailableProviderRegion {
  const factory TmdbAvailableProviderRegion({required String iso3166_1, required String englishName, required String nativeName}) =
      _TmdbAvailableProviderRegion;

  @override
  factory TmdbAvailableProviderRegion.fromJson(Map<String, dynamic> json) => _$TmdbAvailableProviderRegionFromJson(json);
}

/// One streaming service as TMDB lists it under a region's `flatrate` / `rent` / `buy` arrays.
///
/// The JSON keys are TMDB's own (`display_priority`, `logo_path`, ...), so the same class parses
/// both the live `watch/providers` payload and a stored snapshot verbatim. [logoPath] is TMDB's
/// bare image path until a caller builds a URL out of it.
@freezed
abstract class TmdbWatchProvider with _$TmdbWatchProvider {
  const factory TmdbWatchProvider({
    @JsonKey(name: 'display_priority') @Default(0) int displayPriority,
    @JsonKey(name: 'logo_path') String? logoPath,
    @JsonKey(name: 'provider_name') required String providerName,
    @JsonKey(name: 'provider_id') required int providerId,
  }) = _TmdbWatchProvider;

  @override
  factory TmdbWatchProvider.fromJson(Map<String, dynamic> json) => _$TmdbWatchProviderFromJson(json);
}
