import 'dart:math';

import 'package:ticketbox/api/tmdb/image_size_util.dart';
import 'package:ticketbox/api/tmdb/v3/people/model/person_details.dart';
import 'package:ticketbox/api/tmdb/v3/people/person_details_api.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';
import 'package:ticketbox/database/sql_store/rating/user_rating_repository.dart';
import 'package:ticketbox/database/sql_store/show_state/show_state_repository.dart';
import 'package:ticketbox/database/sql_store/watchlist/watchlist_repo.dart';
import 'package:ticketbox/service/person/person_credit.dart';

/// A person's details, assembled fresh on every visit — unlike movies/shows there is no local
/// table backing this: a person is opened rarely (only from a cast card) and the data does not
/// need to survive offline, so caching it would only add a table and a `schemaVersion` bump for
/// little benefit.
class PersonDetails {
  final String? name;
  final String? photoUrl;
  final String? biography;
  final String? knownForDepartment;
  final String? birthday;
  final String? death;
  final String? birthplace;

  /// Other names TMDB lists the person under, blanks removed.
  final List<String> alsoKnownAs;

  final String? imdbId;

  /// Full URLs, ready to open — TMDB only carries the bare handles/ids, the hosts are added here.
  final String? twitter;
  final String? instagram;
  final String? facebook;

  /// TMDB carries no Wikipedia link; this is the Wikidata item page, which links out to every
  /// language edition.
  final String? wikipedia;
  final String? homepage;

  /// Every title the person acted in, one card per title, in display order and not yet marked
  /// against the library (see [PersonService.withLibraryMarks]).
  final List<PersonCredit> filmography;

  const PersonDetails({
    required this.name,
    required this.photoUrl,
    required this.biography,
    required this.knownForDepartment,
    required this.birthday,
    required this.death,
    required this.birthplace,
    required this.alsoKnownAs,
    required this.imdbId,
    required this.twitter,
    required this.instagram,
    required this.facebook,
    required this.wikipedia,
    required this.homepage,
    required this.filmography,
  });
}

/// Thrown by [PersonService.get] when TMDB has no person with the requested id.
class PersonNotFoundException implements Exception {
  final int personTmdbId;

  const PersonNotFoundException(this.personTmdbId);

  @override
  String toString() => 'PersonNotFoundException: no TMDB person with id $personTmdbId';
}

/// The person page's data. The page is read-only — it writes no row, creates no poster and fires
/// no per-title request — so it is two steps and both are cheap:
///
/// 1. [get] — one TMDB request (`/person/{id}` with the combined credits and external ids
///    appended), folded in memory by [filmography] into one card per title.
/// 2. [withLibraryMarks] — a handful of whole-table reads of the user's own data (plays, show
///    progress, watchlist, ratings), stamped onto the cards. Never a query per title.
///
/// The filmography cards carry TMDB's own artwork path and score, so nothing has to be resolved
/// through the `posters` table; the grid tiles render the payload as it is.
class PersonService {
  /// One TMDB request: `/person/{id}` with `combined_credits` and `external_ids` appended.
  Future<PersonDetails> get(int personTmdbId, PosterQualityOption quality) async {
    final details = await TmdbPersonDetailsApi().get(personTmdbId);
    if (details == null) {
      throw PersonNotFoundException(personTmdbId);
    }

    final externalIds = details.externalIds;

    return PersonDetails(
      name: details.name,
      photoUrl: TmdbImageBuildUtil.buildUrl(details.profilePath, imageSize: TmdbImageBuildUtil.getProfileImageQuality(quality)),
      biography: _nullIfEmpty(details.biography),
      knownForDepartment: _nullIfEmpty(details.knownForDepartment),
      birthday: _nullIfEmpty(details.birthday),
      death: _nullIfEmpty(details.deathday),
      birthplace: _nullIfEmpty(details.placeOfBirth),
      alsoKnownAs: details.alsoKnownAs.map((alias) => alias.trim()).where((alias) => alias.isNotEmpty).toList(),
      imdbId: _nullIfEmpty(details.imdbId) ?? _nullIfEmpty(externalIds?.imdbId),
      twitter: _social('https://x.com/', externalIds?.twitterId),
      instagram: _social('https://www.instagram.com/', externalIds?.instagramId),
      facebook: _social('https://www.facebook.com/', externalIds?.facebookId),
      wikipedia: _social('https://www.wikidata.org/wiki/', externalIds?.wikidataId),
      homepage: _nullIfEmpty(details.homepage),
      filmography: filmography(details.combinedCredits?.cast ?? const [], posterSize: TmdbImageBuildUtil.getPosterImageQuality(quality)),
    );
  }

  /// The cast credits as filmography cards: movies and shows only, **one card per title**, in a
  /// deterministic display order, with no cap (the grid is lazy, the page filters client-side).
  ///
  /// TMDB lists a person once per character, so an actor with two parts in one show appears
  /// twice; those entries fold into one card keyed on (kind, id) — never the id alone, because a
  /// movie and a show can share a TMDB id:
  ///
  /// - title, date, score and poster come from the first entry seen;
  /// - the characters are every distinct non-blank part, in first-seen order, joined with ` / `
  ///   (TMDB repeats a part per season, so an exact duplicate is dropped);
  /// - a show's episode count is the **largest** part's, not the sum — parts can share episodes;
  /// - a score of 0 means "no votes" and becomes null.
  ///
  /// Order: undated titles first (announced work, as TMDB's own page does), then newest first,
  /// then title (case-insensitive), kind and id — so cards never swap places between renders.
  static List<PersonCredit> filmography(List<TmdbPersonCredit> cast, {required String posterSize}) {
    // A map literal keeps insertion order, which is what "first seen" relies on.
    final folded = <(PersonCreditKind, int), _CreditFold>{};
    for (final credit in cast) {
      final kind = credit.isMovie ? PersonCreditKind.movie : (credit.isShow ? PersonCreditKind.show : null);
      final title = _nullIfEmpty(credit.displayTitle);
      if (kind == null || credit.id == 0 || title == null) {
        continue;
      }
      folded.putIfAbsent((kind, credit.id), () => _CreditFold(kind, credit.id, title, credit)).add(credit);
    }

    final cards = [for (final fold in folded.values) fold.toCredit(posterSize)];
    cards.sort(_byDisplayOrder);
    return cards;
  }

  static int _byDisplayOrder(PersonCredit a, PersonCredit b) {
    final dateA = a.date;
    final dateB = b.date;
    if (dateA == null && dateB != null) return -1;
    if (dateA != null && dateB == null) return 1;
    if (dateA != null && dateB != null) {
      // ISO `yyyy-MM-dd` strings compare correctly as text.
      final byDate = dateB.compareTo(dateA);
      if (byDate != 0) return byDate;
    }

    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (byTitle != 0) return byTitle;

    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;

    return a.tmdbId.compareTo(b.tmdbId);
  }

  /// [credits] with their library flags set, from five whole-table reads of the user's own data
  /// — bounded by what the user has done, not by the filmography, and never a query per title.
  ///
  /// - a movie is [PersonCredit.watched] and [PersonCredit.inHistory] when it has any play;
  /// - a show is [PersonCredit.inHistory] when any episode has a play (specials included) and
  ///   [PersonCredit.watched] only when its progress says every aired episode is — on the person
  ///   page a show's check mark means *finished*, unlike the poster table's any-play flag;
  /// - [PersonCredit.inLibrary] means the user has a play, a watchlist entry or a rating for the
  ///   title. Not "has a movies/shows row": Discover, Search and the cast lists write those for
  ///   anything the user merely scrolled past.
  Future<List<PersonCredit>> withLibraryMarks(List<PersonCredit> credits) async {
    if (credits.isEmpty) {
      return credits;
    }

    final (watchedMovies, startedShows, completedShows, watchlist, ratings) = await (
      HistoryRepo().getWatchedMovieIds(),
      HistoryRepo().getWatchedShowIds(),
      ShowStateRepo().getFinishedIds(),
      WatchlistRepo().getAll(),
      UserRatingRepo().getAll(),
    ).wait;

    // Only the title-level rows: a season or episode on the watchlist, or an episode rating, is
    // not a mark on the show itself.
    final watchlistedKeys = <MediaKey>{
      for (final item in watchlist)
        if (item.season == 0 && item.episode == 0) item.key,
    };
    final ratingByKey = <MediaKey, int>{
      for (final item in ratings)
        if (item.season == 0 && item.episode == 0) item.key: item.rating,
    };

    return [
      for (final credit in credits)
        () {
          final inHistory = credit.isMovie ? watchedMovies.contains(credit.tmdbId) : startedShows.contains(credit.tmdbId);
          final watched = credit.isMovie ? inHistory : completedShows.contains(credit.tmdbId);
          final watchlisted = watchlistedKeys.contains(credit.key);
          final userRating = ratingByKey[credit.key];
          return credit.copyWith(
            inLibrary: inHistory || watchlisted || userRating != null,
            watched: watched,
            inHistory: inHistory,
            watchlisted: watchlisted,
            userRating: userRating,
          );
        }(),
    ];
  }

  static String? _social(String baseUrl, String? id) {
    final handle = _nullIfEmpty(id);
    return handle == null ? null : '$baseUrl$handle';
  }

  static int? _year(String? date) {
    if (date == null || date.length < 4) {
      return null;
    }
    return int.tryParse(date.substring(0, 4));
  }

  static String? _nullIfEmpty(String? value) => (value == null || value.trim().isEmpty) ? null : value;
}

/// The parts of one title while [PersonService.filmography] folds them.
class _CreditFold {
  final PersonCreditKind kind;
  final int tmdbId;
  final String title;
  final TmdbPersonCredit first;
  final List<String> characters = [];
  int maxEpisodes = 0;

  _CreditFold(this.kind, this.tmdbId, this.title, this.first);

  void add(TmdbPersonCredit part) {
    final character = part.character?.trim() ?? '';
    if (character.isNotEmpty && !characters.contains(character)) {
      characters.add(character);
    }
    maxEpisodes = max(maxEpisodes, part.episodeCount);
  }

  PersonCredit toCredit(String posterSize) {
    final date = PersonService._nullIfEmpty(first.displayDate);
    final rating = first.voteAverage;
    return PersonCredit(
      kind: kind,
      tmdbId: tmdbId,
      title: title,
      date: date,
      year: PersonService._year(date),
      character: characters.isEmpty ? null : characters.join(' / '),
      episodes: kind == PersonCreditKind.show && maxEpisodes > 0 ? maxEpisodes : null,
      rating: rating == null || rating == 0 ? null : rating,
      posterUrl: TmdbImageBuildUtil.buildUrl(first.posterPath, imageSize: posterSize),
      posterPath: first.posterPath,
    );
  }
}
