import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/ratings_card.dart';

const _both = ExternalRatings(tmdbScore: 8.4, tmdbVotes: 1200, imdbRating: 8.6, imdbVotes: 24000);

/// Pumps [card] on a phone-sized surface, the width the three-column row has to fit.
Future<void> _pump(WidgetTester tester, Widget card) {
  tester.view.physicalSize = const Size(411.42, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ),
  );
}

/// The [index]-th heart (0-based) of the rate sheet's bar.
Finder _sheetHeart(int index) {
  return find.descendant(of: find.byType(RatingBar), matching: find.byType(Image)).at(index);
}

void main() {
  setUpAll(() => ScreenSizeUtil.initWithShortestSize(411.42));

  testWidgets('an unrated title invites a rating next to the community scores', (tester) async {
    await _pump(tester, RatingsCard(userRating: null, externalRatings: _both, onRate: (_) {}, onRemoveRating: null));

    expect(find.text('84%'), findsOneWidget);
    expect(find.text('8.6'), findsOneWidget);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Your rating'), findsOneWidget);
    expect(find.byType(RatingBar), findsNothing);
  });

  testWidgets('a rated title shows the value', (tester) async {
    await _pump(tester, RatingsCard(userRating: '7', externalRatings: _both, onRate: (_) {}, onRemoveRating: () {}));

    expect(find.text('7/10', findRichText: true), findsOneWidget);
    expect(find.text('Rate'), findsNothing);
  });

  testWidgets('the user column stays when no community rating exists', (tester) async {
    await _pump(tester, RatingsCard(userRating: null, externalRatings: null, onRate: (_) {}, onRemoveRating: null));

    expect(find.text('No ratings yet'), findsOneWidget);
    expect(find.text('Rate'), findsOneWidget);
  });

  testWidgets('picking a heart does nothing until Rate confirms it', (tester) async {
    final rated = <int>[];
    await _pump(tester, RatingsCard(userRating: null, externalRatings: _both, onRate: rated.add, onRemoveRating: null));

    await tester.tap(find.text('Rate'));
    await tester.pumpAndSettle();
    expect(find.text('Tap a heart'), findsOneWidget);
    expect(find.text('Remove rating'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(_sheetHeart(7));
    await tester.pumpAndSettle();
    expect(find.text('8/10'), findsOneWidget);
    expect(rated, isEmpty);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(rated, [8]);
    expect(find.byType(RatingBar), findsNothing);
  });

  testWidgets('dismissing the sheet keeps the rating', (tester) async {
    final rated = <int>[];
    await _pump(tester, RatingsCard(userRating: '5', externalRatings: _both, onRate: rated.add, onRemoveRating: () {}));

    await tester.tap(find.text('Your rating'));
    await tester.pumpAndSettle();
    await tester.tap(_sheetHeart(8));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.byType(RatingBar), findsNothing);
    expect(rated, isEmpty);
  });

  testWidgets('the sheet cannot confirm the rating it opened with, and can remove it', (tester) async {
    var removed = 0;
    await _pump(
      tester,
      RatingsCard(userRating: '5', externalRatings: _both, onRate: (_) => fail('not rated'), onRemoveRating: () => removed++),
    );

    await tester.tap(find.text('Your rating'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('5/10')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('Remove rating'));
    await tester.pumpAndSettle();
    expect(removed, 1);
  });

  testWidgets('the column is inert while an action is in flight', (tester) async {
    await _pump(tester, const RatingsCard(userRating: '5', externalRatings: _both, onRate: null, onRemoveRating: null));

    await tester.tap(find.text('Your rating'));
    await tester.pumpAndSettle();
    expect(find.byType(RatingBar), findsNothing);
  });

  testWidgets('the season card keeps its read-only average and has no user column', (tester) async {
    await _pump(tester, const RatingsCard.season(externalRatings: _both, episodeAverage: (average: 7.5, count: 4)));

    expect(find.byType(RatingBar), findsOneWidget);
    expect(find.text('Your rating'), findsNothing);
    expect(find.text('Rate'), findsNothing);
    expect(find.textContaining('Average of your 4 rated episodes'), findsOneWidget);
  });
}
