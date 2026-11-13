import 'package:ticketbox/api/tmdb/v3/model/credit/person_credit.dart';

/// One actor as the Cast section renders them.
class CastMember {
  final String name;

  /// Every character they play here, already joined for display
  final String characterName;

  /// TMDB's relative headshot path, or null when TMDB has none — which the card renders as its
  /// person-outline placeholder. The artwork layer turns it into a local file or a URL.
  final String? profilePath;

  /// The person's TMDB id, so a tap on their card can open their Person details page.
  final int personTmdbId;

  const CastMember({required this.name, required this.characterName, required this.profilePath, required this.personTmdbId});

  /// From a `cast[]` / `aggregate_credits.cast[]` / `guest_stars[]` entry: the flat endpoints
  /// carry one `character`, the aggregate ones a `roles[]` list.
  factory CastMember.fromCredit(TmdbCastPerson person) {
    final roles = person.roles.map((role) => role.character).whereType<String>().where((c) => c.isNotEmpty);
    final characters = roles.isNotEmpty ? roles.join(' / ') : (person.character ?? '');
    return CastMember(name: person.name, characterName: characters, profilePath: person.profilePath, personTmdbId: person.id);
  }
}

/// An item's cast, split the way the section's two chips are.
class ItemCast {
  final List<CastMember> regulars;
  final List<CastMember> guests;

  const ItemCast(this.regulars, this.guests);

  static const ItemCast empty = ItemCast([], []);

  /// Deduplicated on person: a guest who is also a regular stays a regular.
  factory ItemCast.fromCredits(List<TmdbCastPerson> regulars, [List<TmdbCastPerson> guests = const []]) {
    final seen = <int>{};
    final regularMembers = <CastMember>[];
    for (final person in regulars) {
      if (seen.add(person.id)) {
        regularMembers.add(CastMember.fromCredit(person));
      }
    }
    final guestMembers = <CastMember>[];
    for (final person in guests) {
      if (seen.add(person.id)) {
        guestMembers.add(CastMember.fromCredit(person));
      }
    }
    return ItemCast(regularMembers, guestMembers);
  }

  bool get isEmpty => regulars.isEmpty && guests.isEmpty;
}
