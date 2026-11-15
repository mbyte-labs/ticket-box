import 'package:ticketbox/service/person/person_credit.dart';

/// The Filmography section's segmented filter. Client-side only — the whole credit list is
/// already on the device — and never persisted: the section always opens on everything.
enum PersonFilmographyFilter {
  all,
  movies,
  shows;

  bool accepts(PersonCredit credit) => switch (this) {
    all => true,
    movies => credit.isMovie,
    shows => credit.isShow,
  };

  /// The segment's text, with the count it would show: `All 42`, `Movies 30`, `Shows 12`.
  String label({required int movieCount, required int showCount}) => switch (this) {
    all => 'All ${movieCount + showCount}',
    movies => 'Movies $movieCount',
    shows => 'Shows $showCount',
  };
}
