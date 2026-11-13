import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/tmdb_data_set.dart';
import 'package:ticketbox/service/tmdb_account/tmdb_sync_support.dart';

void main() {
  group('rating translation', () {
    test('TMDB half steps round half up onto the 1–10 scale', () {
      expect(TmdbSyncSupport.roundTmdbRating(7.5), 8);
      expect(TmdbSyncSupport.roundTmdbRating(7.4), 7);
      expect(TmdbSyncSupport.roundTmdbRating(7.0), 7);
      expect(TmdbSyncSupport.roundTmdbRating(9.5), 10);
    });

    test('the ends of the scale are clamped', () {
      expect(TmdbSyncSupport.roundTmdbRating(0.5), 1);
      expect(TmdbSyncSupport.roundTmdbRating(0), 1);
      expect(TmdbSyncSupport.roundTmdbRating(10), 10);
      expect(TmdbSyncSupport.roundTmdbRating(11), 10);
    });

    test('the app\'s whole rating goes to TMDB as it is', () {
      expect(TmdbSyncSupport.toTmdbRating(8), 8.0);
      expect(TmdbSyncSupport.toTmdbRating(1), 1.0);
    });
  });

  group('what has a place on TMDB', () {
    test('ratings: movies, shows and episodes, never a season', () {
      expect(TmdbSyncSupport.canSync(TmdbDataSet.ratings, const MediaKey.movie(1)), isTrue);
      expect(TmdbSyncSupport.canSync(TmdbDataSet.ratings, const MediaKey.show(1)), isTrue);
      expect(TmdbSyncSupport.canSync(TmdbDataSet.ratings, const MediaKey.episode(1, 1, 1)), isTrue);
      expect(TmdbSyncSupport.canSync(TmdbDataSet.ratings, const MediaKey.season(1, 1)), isFalse);
    });

    test('watchlist and favorite: whole titles only', () {
      for (final dataSet in [TmdbDataSet.watchlist, TmdbDataSet.favorites]) {
        expect(TmdbSyncSupport.canSync(dataSet, const MediaKey.movie(1)), isTrue, reason: dataSet.name);
        expect(TmdbSyncSupport.canSync(dataSet, const MediaKey.show(1)), isTrue, reason: dataSet.name);
        expect(TmdbSyncSupport.canSync(dataSet, const MediaKey.season(1, 1)), isFalse, reason: dataSet.name);
        expect(TmdbSyncSupport.canSync(dataSet, const MediaKey.episode(1, 1, 1)), isFalse, reason: dataSet.name);
      }
    });
  });
}
