import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/ui/pages/details/person/person_text_format.dart';

/// The hero's meta line and the facts' dates: formatted like `18 Dec 1963`, with an age only when
/// the dates it needs are full dates — TMDB sometimes knows only a year.
void main() {
  final now = DateTime(2026, 11, 3);

  group('formatDate', () {
    test('formats a full date and leaves a partial one alone', () {
      expect(PersonTextFormat.formatDate('1963-12-18'), '18 Dec 1963');
      expect(PersonTextFormat.formatDate('1963'), '1963');
      expect(PersonTextFormat.formatDate(''), isNull);
      expect(PersonTextFormat.formatDate(null), isNull);
    });
  });

  group('lifeLine', () {
    test('alive with a full birthday carries the age, counted around the birthday', () {
      expect(PersonTextFormat.lifeLine('1963-12-18', null, now), 'Born 18 Dec 1963 (age 62)');
      expect(PersonTextFormat.lifeLine('1963-11-03', null, now), 'Born 3 Nov 1963 (age 63)');
    });

    test('alive with a year-only birthday has no age', () {
      expect(PersonTextFormat.lifeLine('1963', null, now), 'Born 1963');
    });

    test('deceased with two full dates carries the age at death', () {
      expect(PersonTextFormat.lifeLine('1930-01-12', '2001-05-05', now), '12 Jan 1930 – 5 May 2001 (aged 71)');
    });

    test('deceased with a partial date on either side has no age', () {
      expect(PersonTextFormat.lifeLine('1930-01-12', '2001', now), '12 Jan 1930 – 2001');
      expect(PersonTextFormat.lifeLine('1930', '2001-05-05', now), '1930 – 5 May 2001');
    });

    test('no birthday, no line', () {
      expect(PersonTextFormat.lifeLine(null, '2001-05-05', now), isNull);
    });
  });

  group('metaLine', () {
    test('joins whatever exists', () {
      expect(
        PersonTextFormat.metaLine(
          knownForDepartment: 'Acting',
          birthday: '1963-12-18',
          deathday: null,
          placeOfBirth: 'Shawnee, Oklahoma, USA',
          now: now,
        ),
        'Acting · Born 18 Dec 1963 (age 62) · Shawnee, Oklahoma, USA',
      );
      expect(PersonTextFormat.metaLine(knownForDepartment: null, birthday: null, deathday: null, placeOfBirth: 'Paris', now: now), 'Paris');
      expect(PersonTextFormat.metaLine(knownForDepartment: null, birthday: null, deathday: null, placeOfBirth: null, now: now), isNull);
    });
  });
}
