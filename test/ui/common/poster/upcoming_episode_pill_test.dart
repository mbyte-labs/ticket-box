import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/database/sql_store/progress/show_progress_queries.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/ui/common/poster/pills/upcoming_episode_pill.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_top_left.dart';

UpNextRow _row({required bool aired, String? airDate, String? episodeType}) {
  return UpNextRow(
    next: NextEpisode(
      showTmdbId: 1396,
      season: 2,
      episode: 1,
      title: 'Seven Thirty-Seven',
      airDate: airDate,
      episodeType: episodeType,
      aired: aired,
    ),
    showTitle: 'Breaking Bad',
    showPosterPath: null,
    seasonPosterPath: null,
    lastWatchedAt: null,
  );
}

void main() {
  group('label', () {
    test('a dated episode shows its air date', () {
      expect(UpcomingEpisodePill.label('2027-10-20'), 'Airs 20.10.2027');
    });

    test('an undated or unparsable date reads TBA', () {
      expect(UpcomingEpisodePill.label(null), 'Airs TBA');
      expect(UpcomingEpisodePill.label('garbage'), 'Airs TBA');
    });
  });

  group('PosterModelBuilder.upNext', () {
    test('an unaired episode is upcoming and carries its date', () {
      final model = PosterModelBuilder.upNext(_row(aired: false, airDate: '2027-10-20'));
      expect(model.upcoming, isTrue);
      expect(model.airDate, '2027-10-20');
    });

    test('an aired episode is not upcoming', () {
      final model = PosterModelBuilder.upNext(_row(aired: true, airDate: '2020-01-01'));
      expect(model.upcoming, isFalse);
    });
  });

  group('PosterTopLeftPills', () {
    Future<void> pump(WidgetTester tester, Widget child) {
      return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    }

    testWidgets('an upcoming season premiere stacks both pills', (tester) async {
      final model = PosterModelBuilder.upNext(_row(aired: false, airDate: '2027-10-20', episodeType: 'season_premiere'));
      await pump(tester, PosterTopLeftPills(model));
      expect(find.text('Airs 20.10.2027'), findsOneWidget);
      expect(find.text('Season Premiere'), findsOneWidget);
    });

    testWidgets('an aired episode has no airing pill', (tester) async {
      final model = PosterModelBuilder.upNext(_row(aired: true, airDate: '2020-01-01'));
      await pump(tester, PosterTopLeftPills(model));
      expect(find.byType(UpcomingEpisodePill), findsNothing);
      expect(find.textContaining('Airs'), findsNothing);
    });
  });
}
