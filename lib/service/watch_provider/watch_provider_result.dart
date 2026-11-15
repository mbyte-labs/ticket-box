import 'package:ticketbox/api/tmdb/v3/watch_providers/model.dart';

/// One region's streaming answer for a title: the services carrying it, plus the JustWatch page
/// that lists every offer.
///
/// TMDB returns a single [justWatchLink] per payload rather than one per provider, so the link
/// belongs to the row as a whole — every logo in a *Watch now* row opens the same page.
///
/// The season and episode endpoints narrow [providers] but answer with the *show's* link, not a
/// season- or episode-scoped one (verified against TMDB: all three levels return the same
/// `/tv/{id}/watch?locale=` URL). A season page's tap therefore lands on the show's offer page,
/// which is the closest thing TMDB exposes.
///
/// A plain class rather than a `@freezed` one: nothing here needs `copyWith` or `fromJson` (the
/// cache serializes [TmdbWatchProvider], which already has both), so it stays out of codegen.
class WatchProviderResult {
  final List<TmdbWatchProvider> providers;

  /// `null` when TMDB has no offer link for this title in this region.
  final String? justWatchLink;

  const WatchProviderResult({required this.providers, required this.justWatchLink});
}
