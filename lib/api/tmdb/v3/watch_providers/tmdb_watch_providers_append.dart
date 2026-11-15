import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/api/tmdb/v3/watch_providers/model.dart';

part 'tmdb_watch_providers_append.freezed.dart';
part 'tmdb_watch_providers_append.g.dart';

/// The `watch/providers` object `append_to_response=watch/providers` adds to movie and show
/// details: one [TmdbRegionProviders] per ISO 3166-1 country code. TMDB sends every country it
/// knows (over a hundred); a stored snapshot keeps only the configured one.
@Freezed(toJson: false)
abstract class TmdbWatchProvidersAppend with _$TmdbWatchProvidersAppend {
  const TmdbWatchProvidersAppend._();

  const factory TmdbWatchProvidersAppend({@Default(<String, TmdbRegionProviders>{}) Map<String, TmdbRegionProviders> results}) =
      _TmdbWatchProvidersAppend;

  factory TmdbWatchProvidersAppend.fromJson(Map<String, dynamic> json) => _$TmdbWatchProvidersAppendFromJson(json);

  /// The offers in [regionIso3166_1], or null when TMDB lists none there.
  TmdbRegionProviders? forRegion(String regionIso3166_1) => results[regionIso3166_1];
}

/// One country's offers. [link] is the JustWatch page listing every offer — one per title, not
/// one per provider.
@Freezed(toJson: false)
abstract class TmdbRegionProviders with _$TmdbRegionProviders {
  const factory TmdbRegionProviders({
    String? link,
    @Default(<TmdbWatchProvider>[]) List<TmdbWatchProvider> flatrate,
    @Default(<TmdbWatchProvider>[]) List<TmdbWatchProvider> rent,
    @Default(<TmdbWatchProvider>[]) List<TmdbWatchProvider> buy,
    @Default(<TmdbWatchProvider>[]) List<TmdbWatchProvider> free,
    @Default(<TmdbWatchProvider>[]) List<TmdbWatchProvider> ads,
  }) = _TmdbRegionProviders;

  factory TmdbRegionProviders.fromJson(Map<String, dynamic> json) => _$TmdbRegionProvidersFromJson(json);
}
