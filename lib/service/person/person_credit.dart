import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';

part 'person_credit.freezed.dart';

/// The two kinds of title a person's acting credits resolve to. TMDB's `tv` is a [show] here.
enum PersonCreditKind {
  movie,
  show;

  ItemType get itemType => this == movie ? ItemType.movie : ItemType.show;

  String get label => this == movie ? 'Movie' : 'Show';
}

/// One filmography card: a title the person acted in, folded from every part TMDB lists them under
/// (see `PersonService.filmography`) and marked against the user's library
/// (`PersonService.withLibraryMarks`). Built in memory from the credits payload — nothing about a
/// person is ever persisted.
@freezed
abstract class PersonCredit with _$PersonCredit {
  const PersonCredit._();

  const factory PersonCredit({
    required PersonCreditKind kind,
    required int tmdbId,
    required String title,

    /// The movie's release date or the show's first air date, as TMDB sent it (`yyyy-MM-dd`,
    /// occasionally shorter); null when TMDB has none.
    required String? date,
    required int? year,

    /// Every part the person played in the title, joined with ` / `; null when TMDB names none.
    required String? character,

    /// Shows only: the most episodes any one part spans. Null for movies and when unknown.
    required int? episodes,

    /// TMDB's community score; null when the title has no votes.
    required double? rating,
    required String? posterUrl,

    /// TMDB's relative poster path (`/abc.jpg`), what the shared poster tile resolves artwork from.
    String? posterPath,

    /// The user has a play, a watchlist entry or a rating for the title.
    @Default(false) bool inLibrary,

    /// A movie with a play; a show whose every aired episode is watched.
    @Default(false) bool watched,

    /// A movie with a play; a show with at least one episode play, specials included.
    @Default(false) bool inHistory,
    @Default(false) bool watchlisted,
    int? userRating,
  }) = _PersonCredit;

  bool get isMovie => kind == PersonCreditKind.movie;

  bool get isShow => kind == PersonCreditKind.show;

  MediaKey get key => isMovie ? MediaKey.movie(tmdbId) : MediaKey.show(tmdbId);

  /// Unique per sibling in a grid: a movie and a show can share a TMDB id.
  String get gridKey => '${kind.name}:$tmdbId';
}
