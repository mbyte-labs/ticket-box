import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/service/artwork/artwork_kind.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';

void main() {
  const paths = ArtworkPaths('/root/assets');

  final show = ArtworkManifest.show(
    tmdbId: 9,
    posterPath: '/p.jpg',
    backdropPath: '/b.jpg',
    seasonPosterPaths: {10: '/s10.jpg', 2: '/s2.jpg', 1: null, 3: '/../bad.jpg'},
    stillPaths: {(2, 1): '/e21.jpg', (1, 2): '/e12.jpg', (1, 1): '/e11.jpg', (1, 3): null},
    castProfilePaths: {'/f1.jpg', '/f2.jpg', 'not-safe'},
  );

  test('refs come in priority order and skip null or unsafe paths', () {
    expect(show.refs(), [
      const ArtworkRef.poster(MediaKey.show(9), '/p.jpg'),
      const ArtworkRef.backdrop(MediaKey.show(9), '/b.jpg'),
      ArtworkRef.seasonPoster(9, 2, '/s2.jpg'),
      ArtworkRef.seasonPoster(9, 10, '/s10.jpg'),
      ArtworkRef.still(9, 1, 1, '/e11.jpg'),
      ArtworkRef.still(9, 1, 2, '/e12.jpg'),
      ArtworkRef.still(9, 2, 1, '/e21.jpg'),
      const ArtworkRef.cast(MediaKey.show(9), '/f1.jpg'),
      const ArtworkRef.cast(MediaKey.show(9), '/f2.jpg'),
    ]);
  });

  test('primaryRefs is the poster and the backdrop only', () {
    expect(show.primaryRefs(), [
      const ArtworkRef.poster(MediaKey.show(9), '/p.jpg'),
      const ArtworkRef.backdrop(MediaKey.show(9), '/b.jpg'),
    ]);
    expect(ArtworkManifest.movie(tmdbId: 1, posterPath: null, backdropPath: '/b.jpg').primaryRefs(), [
      const ArtworkRef.backdrop(MediaKey.movie(1), '/b.jpg'),
    ]);
    expect(ArtworkManifest.movie(tmdbId: 1).primaryRefs(), isEmpty);
  });

  test('desiredRelativePaths is the set of files the item wants', () {
    expect(show.desiredRelativePaths(paths), {
      'video/shows/9/poster.jpg',
      'video/shows/9/backdrop.jpg',
      'video/shows/9/seasons/2/poster.jpg',
      'video/shows/9/seasons/10/poster.jpg',
      'video/shows/9/episodes/1-1/still.jpg',
      'video/shows/9/episodes/1-2/still.jpg',
      'video/shows/9/episodes/2-1/still.jpg',
      'video/shows/9/cast/f1.jpg',
      'video/shows/9/cast/f2.jpg',
    });
  });

  test('toJobs carries the owning item, the kind name, the size and the URL per file', () {
    final jobs = show.toJobs(paths, PosterQualityOption.high);
    expect(jobs.map((job) => job.destPath), show.refs().map(paths.relativePath));
    expect(jobs.map((job) => job.mediaType).toSet(), {ItemType.show});
    expect(jobs.map((job) => job.itemId).toSet(), {9});
    expect(jobs.map((job) => job.kind), [
      ArtworkKind.poster.name,
      ArtworkKind.backdrop.name,
      ArtworkKind.seasonPoster.name,
      ArtworkKind.seasonPoster.name,
      ArtworkKind.still.name,
      ArtworkKind.still.name,
      ArtworkKind.still.name,
      ArtworkKind.cast.name,
      ArtworkKind.cast.name,
    ]);
    expect(jobs.first.size, 'w500');
    expect(jobs.first.sourceUrl, 'https://image.tmdb.org/t/p/w500/p.jpg');
    expect(jobs[1].size, 'w1280');
    expect(jobs[1].sourceUrl, 'https://image.tmdb.org/t/p/w1280/b.jpg');
    expect(jobs[4].size, 'original');
    expect(jobs[4].sourceUrl, 'https://image.tmdb.org/t/p/original/e11.jpg');
    expect(jobs.last.size, 'w185');
    expect(jobs.last.sourceUrl, 'https://image.tmdb.org/t/p/w185/f2.jpg');
  });

  test('primaryJobs is the poster and the backdrop', () {
    final jobs = show.primaryJobs(paths, PosterQualityOption.medium);
    expect(jobs.map((job) => job.destPath), ['video/shows/9/poster.jpg', 'video/shows/9/backdrop.jpg']);
    expect(jobs.first.size, 'w342');
  });

  test('a movie manifest has the movie tree and no seasons', () {
    final movie = ArtworkManifest.movie(tmdbId: 4, posterPath: '/p.jpg', backdropPath: null, castProfilePaths: {'/f.jpg'});
    expect(movie.item, const MediaKey.movie(4));
    expect(movie.refs(), [const ArtworkRef.poster(MediaKey.movie(4), '/p.jpg'), const ArtworkRef.cast(MediaKey.movie(4), '/f.jpg')]);
    expect(movie.desiredRelativePaths(paths), {'video/movies/4/poster.jpg', 'video/movies/4/cast/f.jpg'});
    expect(movie.toJobs(paths, PosterQualityOption.medium).map((job) => job.mediaType).toSet(), {ItemType.movie});
  });
}
