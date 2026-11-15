import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/service/catalog/snapshot_pruner.dart';

import 'snapshot_fixtures.dart';

void main() {
  group('movie', () {
    test('keeps only the configured region of watch/providers', () {
      final pruned = SnapshotPruner.movie(rawMovie(), region: 'US');

      final results = (pruned['watch/providers'] as Map)['results'] as Map;
      expect(results.keys, ['US']);
      expect((results['US'] as Map)['link'], 'https://www.themoviedb.org/movie/550/watch?locale=US');
      expect((pruned['watch/providers'] as Map).containsKey('id'), isFalse);
    });

    test('a region TMDB does not list, or no region at all, leaves an empty results map', () {
      expect(((SnapshotPruner.movie(rawMovie(), region: 'FR')['watch/providers'] as Map)['results'] as Map), isEmpty);
      expect(((SnapshotPruner.movie(rawMovie(), region: null)['watch/providers'] as Map)['results'] as Map), isEmpty);
    });

    test('recommendations are capped and similar is emptied when recommendations exist', () {
      final pruned = SnapshotPruner.movie(rawMovie(), region: 'US');

      final recommendations = (pruned['recommendations'] as Map)['results'] as List;
      expect(recommendations.length, SnapshotPruner.relatedLimit);
      expect((recommendations.first as Map)['id'], 101);
      expect((pruned['recommendations'] as Map).containsKey('total_pages'), isFalse);
      expect((pruned['similar'] as Map)['results'], isEmpty);
    });

    test('similar is kept when there are no recommendations', () {
      final raw = rawMovie();
      (raw['recommendations'] as Map<String, dynamic>)['results'] = <dynamic>[];

      final pruned = SnapshotPruner.movie(raw, region: 'US');

      expect(((pruned['similar'] as Map)['results'] as List).length, 3);
    });

    test('images keep the best-voted entries per kind and drop logos', () {
      final pruned = SnapshotPruner.movie(rawMovie(), region: 'US');

      final images = pruned['images'] as Map;
      expect(images.keys, unorderedEquals(['posters', 'backdrops']));
      final posters = (images['posters'] as List).map((p) => (p as Map)['file_path']).toList();
      expect(posters, ['/p-de-9.jpg', '/p-null-8.jpg', '/p-en-7.jpg', '/p-en-6.jpg', '/p-5.jpg']);
      final backdrops = (images['backdrops'] as List).map((p) => (p as Map)['file_path']).toList();
      expect(backdrops, ['/b-2.jpg', '/b-1.jpg']);
    });

    test('cast is capped and crew dropped', () {
      final pruned = SnapshotPruner.movie(rawMovie(), region: 'US');

      final credits = pruned['credits'] as Map;
      expect((credits['cast'] as List).length, SnapshotPruner.castLimit);
      expect(credits['crew'], isEmpty);
    });

    test('only YouTube videos survive', () {
      final pruned = SnapshotPruner.movie(rawMovie(), region: 'US');

      final videos = ((pruned['videos'] as Map)['results'] as List).map((v) => (v as Map)['key']).toList();
      expect(videos, ['yt1', 'yt2']);
    });

    test('everything else is verbatim and the input is not mutated', () {
      final raw = rawMovie();
      final before = rawMovie();

      final pruned = SnapshotPruner.movie(raw, region: 'US');

      expect(raw, equals(before));
      expect(pruned['title'], 'Fight Club');
      expect(pruned['release_dates'], equals(before['release_dates']));
      expect(pruned['external_ids'], equals(before['external_ids']));
    });

    test('pruning is idempotent', () {
      final once = SnapshotPruner.movie(rawMovie(), region: 'US');
      final twice = SnapshotPruner.movie(once, region: 'US');

      expect(twice, equals(once));
    });

    test('a body without the appended sections passes through', () {
      final pruned = SnapshotPruner.movie({'id': 1, 'title': 'Bare'}, region: 'US');

      expect(pruned, {'id': 1, 'title': 'Bare'});
    });
  });

  group('show root', () {
    test('splits the appended seasons out of the root', () {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: 'US');

      expect(pruned.root.keys.where((k) => k.startsWith('season/')), isEmpty);
      expect(pruned.seasons.keys, [1, 2]);
    });

    test('injects the season id from the stub and drops the Mongo _id', () {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: 'US');

      expect(pruned.seasons[1]!['id'], 3624);
      expect(pruned.seasons[2]!['id'], 3625);
      expect(pruned.seasons[1]!.containsKey('_id'), isFalse);
    });

    test('skips a season/N that is TMDB\'s error object', () {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: 'US');

      expect(pruned.seasons.containsKey(99), isFalse);
    });

    test('episodes lose their crew and keep at most the guest-star cap', () {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: 'US');

      final episodes = pruned.seasons[1]!['episodes'] as List;
      final first = episodes.first as Map;
      expect(first['crew'], isEmpty);
      expect((first['guest_stars'] as List).length, SnapshotPruner.guestStarsLimit);
      expect(first['still_path'], '/still-1-1.jpg');
    });

    test('prunes the root like a movie, on aggregate_credits', () {
      final pruned = SnapshotPruner.showRoot(rawShow(), region: 'RO');

      expect(((pruned.root['watch/providers'] as Map)['results'] as Map).keys, ['RO']);
      expect(((pruned.root['aggregate_credits'] as Map)['cast'] as List).length, SnapshotPruner.castLimit);
      expect((pruned.root['aggregate_credits'] as Map)['crew'], isEmpty);
      expect(((pruned.root['similar'] as Map)['results'] as List).length, 2);
      expect(pruned.root['seasons'], equals(rawShow()['seasons']));
    });

    test('is idempotent on the root and the seasons', () {
      final once = SnapshotPruner.showRoot(rawShow(), region: 'US');
      final rootAgain = SnapshotPruner.showRoot(once.root, region: 'US');
      final seasonAgain = SnapshotPruner.season(once.seasons[1]!, id: 3624);

      expect(rootAgain.root, equals(once.root));
      expect(rootAgain.seasons, isEmpty);
      expect(seasonAgain, equals(once.seasons[1]));
    });
  });

  group('bestImagePath', () {
    test('prefers the best-voted English image', () {
      final images = (rawMovie()['images'] as Map)['posters'] as List;

      expect(SnapshotPruner.bestImagePath(images, fallback: '/x.jpg'), '/p-en-7.jpg');
    });

    test('falls back to the best-voted image of any language', () {
      final images = [image('/a.jpg', 1.0, 'de'), image('/b.jpg', 3.0), image('/c.jpg', 2.0, 'fr')];

      expect(SnapshotPruner.bestImagePath(images), '/b.jpg');
    });

    test('falls back to the body path when there are no images', () {
      expect(SnapshotPruner.bestImagePath(null, fallback: '/x.jpg'), '/x.jpg');
      expect(SnapshotPruner.bestImagePath(const [], fallback: '/x.jpg'), '/x.jpg');
      expect(SnapshotPruner.bestImagePath(const []), isNull);
    });
  });
}
