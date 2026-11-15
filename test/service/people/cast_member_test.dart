import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/v3/model/credit/person_credit.dart';
import 'package:ticketbox/service/people/cast_member.dart';

/// Covers [CastMember] and [ItemCast], which turn TMDB's credit entries into what the Cast section
/// renders.
///
/// The parts worth pinning are the ones that differ between TMDB's three credits shapes: the
/// `roles[]` versus `character` split, the `guest_stars` array only the episode payloads carry, and
/// the duplicates TMDB produces that would otherwise show the same face twice.
void main() {
  TmdbCastPerson person(
    int tmdbId, {
    String? profilePath,
    String? character,
    List<TmdbRole> roles = const [],
    int order = 0,
    int totalEpisodeCount = 0,
  }) {
    return TmdbCastPerson(
      id: tmdbId,
      name: 'Person $tmdbId',
      profilePath: profilePath,
      totalEpisodeCount: totalEpisodeCount,
      order: order,
      character: character,
      roles: roles,
    );
  }

  group('CastMember.fromCredit', () {
    test('keeps the name, headshot path and person id TMDB reported', () {
      final member = CastMember.fromCredit(person(10, profilePath: '/face.jpg', character: 'Bob'));

      expect(member.name, 'Person 10');
      expect(member.profilePath, '/face.jpg');
      expect(member.personTmdbId, 10);
      expect(member.characterName, 'Bob');
    });

    test('a person without a headshot keeps a null path rather than being dropped', () {
      expect(CastMember.fromCredit(person(10)).profilePath, isNull);
    });

    group('characterName', () {
      test('joins the aggregate roles for display', () {
        final member = CastMember.fromCredit(
          person(
            10,
            roles: const [
              TmdbRole(character: 'Young Bob', episodeCount: 3),
              TmdbRole(character: 'Old Bob'),
            ],
          ),
        );

        expect(member.characterName, 'Young Bob / Old Bob');
      });

      test('skips roles without a character name', () {
        final member = CastMember.fromCredit(
          person(
            10,
            roles: const [
              TmdbRole(character: 'Bob'),
              TmdbRole(character: null),
              TmdbRole(character: ''),
            ],
          ),
        );

        expect(member.characterName, 'Bob');
      });

      test('falls back to the flat character when there are no roles', () {
        expect(CastMember.fromCredit(person(10, character: 'Bob, Jr.')).characterName, 'Bob, Jr.');
      });

      test('is empty when TMDB names no character at all', () {
        expect(CastMember.fromCredit(person(10)).characterName, '');
      });

      test('roles win over a flat character when both are present', () {
        final member = CastMember.fromCredit(
          person(
            10,
            character: 'Flat',
            roles: const [TmdbRole(character: 'Role')],
          ),
        );

        expect(member.characterName, 'Role');
      });

      test('roles that are all nameless fall back to the flat character', () {
        final member = CastMember.fromCredit(
          person(
            10,
            character: 'Flat',
            roles: const [TmdbRole(character: '')],
          ),
        );

        expect(member.characterName, 'Flat');
      });
    });
  });

  group('ItemCast.fromCredits', () {
    test('cast entries are regulars and guest_stars entries are guests', () {
      final cast = ItemCast.fromCredits([person(10)], [person(20)]);

      expect(cast.regulars.map((m) => m.personTmdbId), [10]);
      expect(cast.guests.map((m) => m.personTmdbId), [20]);
      expect(cast.isEmpty, isFalse);
    });

    test('guests default to none for the aggregate payloads', () {
      final cast = ItemCast.fromCredits([person(10)]);

      expect(cast.regulars.length, 1);
      expect(cast.guests, isEmpty);
    });

    test('keeps the billing order TMDB listed', () {
      final cast = ItemCast.fromCredits([person(30), person(10), person(20)]);

      expect(cast.regulars.map((m) => m.personTmdbId), [30, 10, 20]);
    });

    test('is empty when there are no credits', () {
      expect(ItemCast.fromCredits(const []).isEmpty, isTrue);
      expect(ItemCast.empty.isEmpty, isTrue);
    });

    group('deduplication', () {
      test('the same person listed twice in cast keeps the first, better billed, entry', () {
        final cast = ItemCast.fromCredits([person(10, order: 1, character: 'Lead'), person(10, order: 7, character: 'Extra')]);

        expect(cast.regulars.length, 1);
        expect(cast.regulars.single.characterName, 'Lead');
      });

      test('the same person listed twice in guest_stars keeps one guest', () {
        final cast = ItemCast.fromCredits(const [], [person(20, character: 'A'), person(20, character: 'B')]);

        expect(cast.guests.length, 1);
        expect(cast.guests.single.characterName, 'A');
      });

      test('a guest who is also a regular stays a regular', () {
        final cast = ItemCast.fromCredits([person(10, character: 'Regular')], [person(10, character: 'Guest'), person(20)]);

        expect(cast.regulars.map((m) => m.personTmdbId), [10]);
        expect(cast.regulars.single.characterName, 'Regular');
        expect(cast.guests.map((m) => m.personTmdbId), [20]);
      });
    });
  });
}
