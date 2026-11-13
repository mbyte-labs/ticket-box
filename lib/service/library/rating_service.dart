import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_entity.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/service/library/library_service.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_hooks.dart';

/// A season's derived user rating: the mean of the user's ratings of its episodes, and how many
/// episodes that mean covers.
typedef SeasonRatingAverage = ({double average, int count});

/// The user's own 1–10 ratings. Device-local: a rating is one row in `UserRatings`, overwritten
/// on re-rate — a rating is an opinion, not an event. Rating a title not in the library adds it
/// first (the tracking gate); when the user has connected a TMDB account with rating sync on,
/// [TmdbSyncHooks] queues a copy for TMDB after the local write.
///
/// Movies, shows and episodes are rated directly. Seasons are not: their score is derived from the
/// episode ratings ([seasonAverage]).
class RatingService {
  static final _log = Logger('[Service] RatingService');

  final UserRatingRepo _repo;
  final LibraryService _library;
  final TmdbSyncHooks _hooks;

  RatingService({UserRatingRepo? repo, LibraryService? library, TmdbSyncHooks? hooks})
    : _repo = repo ?? UserRatingRepo(),
      _library = library ?? LibraryService.instance(),
      _hooks = hooks ?? TmdbSyncHooks.instance();

  /// How a [SeasonRatingAverage] is printed, so the season page and the season pill agree.
  static String formatAverage(double average) => average.toStringAsFixed(1);

  Future<void> addRating({required MarkAsWatchedTarget target, required int rating}) async {
    _checkRateable(target);
    _log.info('Rating ${target.key} $rating');
    await _library.ensureTracked(target.key);
    await _repo.insert(
      UserRatingEntity.build(
        type: target.type,
        tmdbId: target.showTmdbId,
        season: target.season,
        episode: target.episode,
        rating: rating,
        ratedAt: DateTime.now().toUtc(),
      ),
    );
    await _hooks.ratingChanged(target.key, rating);
  }

  Future<void> removeRating({required MarkAsWatchedTarget target}) async {
    _checkRateable(target);
    _log.info('Removing the rating of ${target.key}');
    await _repo.deleteByKey(target.key);
    await _hooks.ratingChanged(target.key, null);
    await _library.onReferenceRemoved(target.key);
  }

  /// The average of the user's ratings of this season's episodes, or null when none is rated.
  Future<SeasonRatingAverage?> seasonAverage(int showTmdbId, int season) async {
    final ratings = await _repo.getForSeasonEpisodes(showTmdbId, season);
    if (ratings.isEmpty) {
      return null;
    }
    final sum = ratings.fold<int>(0, (total, item) => total + item.rating);
    return (average: sum / ratings.length, count: ratings.length);
  }

  void _checkRateable(MarkAsWatchedTarget target) {
    if (!target.supportsRating) {
      throw ArgumentError.value(target.key, 'target', 'A ${target.type.name} cannot be rated');
    }
  }
}
