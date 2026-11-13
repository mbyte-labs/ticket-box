/// Trims a TMDB details body down to what a stored snapshot needs, before it is written.
///
/// The snapshot is the provider body *verbatim* except for the cuts below, every one of which
/// removes data no page renders and that would otherwise dominate the document's size:
/// - `watch/providers` is folded to the one configured region (TMDB sends every country it
///   knows, close to half of a movie body); the writer records that region beside the document.
/// - `recommendations` / `similar` keep their first [relatedLimit] rows, and `similar` is emptied
///   when recommendations exist — the *Similar* row only ever falls back to it.
/// - `images` keep the [imagesPerKind] best-voted entries per kind.
/// - cast lists keep the first [castLimit] entries; crew is never rendered and is dropped.
/// - `videos` keep YouTube entries only (the trailer is a YouTube link).
/// - a show's appended `season/N` documents are split out of the root, each with its `id`
///   injected from the matching `seasons[]` stub (an appended season only carries `_id`), its
///   episodes' crew dropped and guest stars capped at [guestStarsLimit].
///
/// Pure and idempotent: pruning an already pruned map yields an equal map. Never mutates its
/// input; the pruned sub-objects are new maps, untouched ones are shared.
class SnapshotPruner {
  const SnapshotPruner._();

  static const int relatedLimit = 10;
  static const int imagesPerKind = 5;
  static const int castLimit = 30;
  static const int guestStarsLimit = 15;

  static final RegExp _appendedSeasonKey = RegExp(r'^season/(\d+)$');

  /// A `/movie/{id}` body.
  static Map<String, dynamic> movie(Map<String, dynamic> raw, {required String? region}) {
    final out = Map<String, dynamic>.of(raw);
    _pruneProviders(out, region);
    _pruneRelated(out);
    _pruneImages(out);
    _pruneCredits(out, 'credits');
    _pruneVideos(out);
    return out;
  }

  /// A `/tv/{id}` body: the pruned root, and every appended `season/N` document (pruned with
  /// [season]) keyed by season number.
  static ({Map<String, dynamic> root, Map<int, Map<String, dynamic>> seasons}) showRoot(
    Map<String, dynamic> raw, {
    required String? region,
  }) {
    final root = <String, dynamic>{};
    final seasons = <int, Map<String, dynamic>>{};
    final stubIds = _stubIds(raw['seasons']);

    for (final entry in raw.entries) {
      final match = _appendedSeasonKey.firstMatch(entry.key);
      final value = entry.value;
      if (match == null) {
        root[entry.key] = value;
        continue;
      }
      // A season that does not exist comes back as TMDB's error object under the same key.
      if (value is! Map<String, dynamic> || value['season_number'] is! int) {
        continue;
      }
      final number = int.parse(match.group(1)!);
      seasons[number] = season(value, id: stubIds[number]);
    }

    _pruneProviders(root, region);
    _pruneRelated(root);
    _pruneImages(root);
    _pruneCredits(root, 'aggregate_credits');
    _pruneVideos(root);
    return (root: root, seasons: seasons);
  }

  /// A season document — standalone `/tv/{id}/season/{n}` or appended. [id] fills in the season's
  /// TMDB id when the document has none (appended seasons carry only a Mongo-style `_id`).
  static Map<String, dynamic> season(Map<String, dynamic> raw, {int? id}) {
    final out = Map<String, dynamic>.of(raw)..remove('_id');
    if (out['id'] is! int && id != null) {
      out['id'] = id;
    }
    final episodes = out['episodes'];
    if (episodes is List) {
      out['episodes'] = [
        for (final episode in episodes)
          if (episode is Map<String, dynamic>) _pruneEpisode(episode) else episode,
      ];
    }
    _pruneImages(out);
    _pruneCredits(out, 'credits');
    return out;
  }

  /// The artwork path a snapshot's convenience column records: the best-voted English image,
  /// else the best-voted one, else [fallback] (the body's own `poster_path` / `backdrop_path`).
  static String? bestImagePath(List<dynamic>? images, {String? fallback}) {
    if (images == null || images.isEmpty) {
      return fallback;
    }
    final sorted = _sortedImages(images);
    for (final image in sorted) {
      if (image['iso_639_1'] == 'en' && image['file_path'] is String) {
        return image['file_path'] as String;
      }
    }
    final first = sorted.first['file_path'];
    return first is String ? first : fallback;
  }

  static Map<int, int> _stubIds(Object? stubs) {
    final ids = <int, int>{};
    if (stubs is List) {
      for (final stub in stubs) {
        if (stub is Map<String, dynamic> && stub['season_number'] is int && stub['id'] is int) {
          ids[stub['season_number'] as int] = stub['id'] as int;
        }
      }
    }
    return ids;
  }

  static Map<String, dynamic> _pruneEpisode(Map<String, dynamic> episode) {
    final out = Map<String, dynamic>.of(episode);
    if (out.containsKey('crew')) {
      out['crew'] = const <dynamic>[];
    }
    final guests = out['guest_stars'];
    if (guests is List && guests.length > guestStarsLimit) {
      out['guest_stars'] = guests.sublist(0, guestStarsLimit);
    }
    return out;
  }

  static void _pruneProviders(Map<String, dynamic> out, String? region) {
    final providers = out['watch/providers'];
    if (providers is! Map<String, dynamic>) {
      return;
    }
    final results = providers['results'];
    final kept = <String, dynamic>{};
    if (region != null && results is Map<String, dynamic> && results[region] != null) {
      kept[region] = results[region];
    }
    out['watch/providers'] = <String, dynamic>{'results': kept};
  }

  static void _pruneRelated(Map<String, dynamic> out) {
    final recommendations = _firstResults(out['recommendations'], relatedLimit);
    if (recommendations != null) {
      out['recommendations'] = <String, dynamic>{'results': recommendations};
    }
    final similar = _firstResults(out['similar'], relatedLimit);
    if (similar != null) {
      final recommendationsExist = recommendations != null && recommendations.isNotEmpty;
      out['similar'] = <String, dynamic>{'results': recommendationsExist ? const <dynamic>[] : similar};
    }
  }

  static List<dynamic>? _firstResults(Object? page, int limit) {
    if (page is! Map<String, dynamic>) {
      return null;
    }
    final results = page['results'];
    if (results is! List) {
      return const [];
    }
    return results.length > limit ? results.sublist(0, limit) : List<dynamic>.of(results);
  }

  static void _pruneImages(Map<String, dynamic> out) {
    final images = out['images'];
    if (images is! Map<String, dynamic>) {
      return;
    }
    final kept = <String, dynamic>{};
    for (final kind in const ['posters', 'backdrops', 'stills']) {
      final list = images[kind];
      if (list is List) {
        final sorted = _sortedImages(list);
        kept[kind] = sorted.length > imagesPerKind ? sorted.sublist(0, imagesPerKind) : sorted;
      }
    }
    out['images'] = kept;
  }

  /// Best-voted first; a stable sort keeps TMDB's order among equal votes, which is what makes
  /// pruning idempotent.
  static List<Map<String, dynamic>> _sortedImages(List<dynamic> images) {
    final maps = images.whereType<Map<String, dynamic>>().toList();
    final indexed = maps.asMap().entries.toList()
      ..sort((a, b) {
        final byVotes = _vote(b.value).compareTo(_vote(a.value));
        return byVotes != 0 ? byVotes : a.key.compareTo(b.key);
      });
    return indexed.map((e) => e.value).toList();
  }

  static double _vote(Map<String, dynamic> image) {
    final value = image['vote_average'];
    return value is num ? value.toDouble() : 0;
  }

  static void _pruneCredits(Map<String, dynamic> out, String key) {
    final credits = out[key];
    if (credits is! Map<String, dynamic>) {
      return;
    }
    final cast = credits['cast'];
    final kept = <String, dynamic>{
      'cast': cast is List ? (cast.length > castLimit ? cast.sublist(0, castLimit) : List<dynamic>.of(cast)) : const <dynamic>[],
      'crew': const <dynamic>[],
    };
    final guests = credits['guest_stars'];
    if (guests is List) {
      kept['guest_stars'] = guests.length > guestStarsLimit ? guests.sublist(0, guestStarsLimit) : List<dynamic>.of(guests);
    }
    out[key] = kept;
  }

  static void _pruneVideos(Map<String, dynamic> out) {
    final videos = out['videos'];
    if (videos is! Map<String, dynamic>) {
      return;
    }
    final results = videos['results'];
    out['videos'] = <String, dynamic>{
      'results': [
        if (results is List)
          for (final video in results)
            if (video is Map<String, dynamic> && (video['site'] as String?)?.toLowerCase() == 'youtube') video,
      ],
    };
  }
}
