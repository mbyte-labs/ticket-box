import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/aggregate_credits.dart';

/// Guards the one model that is parsed from three differently shaped TMDB endpoints: the show and
/// season *aggregate* credits, and the flat episode credits.
///
/// `guest_stars` and `order` appear in some of those payloads and not others, so both have to be
/// optional — a throw here would cost the whole Cast section its headshots.
void main() {
  test('episode credits parse their guest stars', () {
    final credits = TmdbCredits.fromJson({
      'cast': [
        {'id': 500, 'name': 'A Regular', 'profile_path': '/regular.jpg', 'order': 0},
      ],
      'guest_stars': [
        {'id': 600, 'name': 'A Guest', 'profile_path': '/guest.jpg', 'order': 3},
      ],
      'crew': <Map<String, dynamic>>[],
    });

    expect(credits.cast.single.id, 500);
    expect(credits.guestStars.single.id, 600);
    expect(credits.guestStars.single.profilePath, '/guest.jpg');
  });

  test('aggregate credits parse without a guest_stars key', () {
    final credits = TmdbCredits.fromJson({
      'cast': [
        {'id': 500, 'name': 'A Regular', 'profile_path': '/regular.jpg', 'total_episode_count': 12, 'order': 0},
      ],
      'crew': <Map<String, dynamic>>[],
    });

    expect(credits.guestStars, isEmpty);
    expect(credits.cast.single.totalEpisodeCount, 12);
  });

  test('a cast entry with no order still parses', () {
    final credits = TmdbCredits.fromJson({
      'cast': [
        {'id': 500, 'name': 'A Regular', 'profile_path': null},
      ],
      'crew': <Map<String, dynamic>>[],
    });

    expect(credits.cast.single.order, 0);
    expect(credits.cast.single.profilePath, isNull);
  });

  test('a null guest_stars key is treated as absent', () {
    final credits = TmdbCredits.fromJson({'cast': <Map<String, dynamic>>[], 'crew': <Map<String, dynamic>>[], 'guest_stars': null});

    expect(credits.guestStars, isEmpty);
  });
}
