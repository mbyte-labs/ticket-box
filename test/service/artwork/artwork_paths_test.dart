import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';

void main() {
  const paths = ArtworkPaths('/data/app/files/assets');

  group('isSafeTmdbPath', () {
    test('accepts TMDB image paths in any case', () {
      expect(ArtworkPaths.isSafeTmdbPath('/abc.jpg'), isTrue);
      expect(ArtworkPaths.isSafeTmdbPath('/aBc_1-2.JPEG'), isTrue);
      expect(ArtworkPaths.isSafeTmdbPath('/x.png'), isTrue);
      expect(ArtworkPaths.isSafeTmdbPath('/x.webp'), isTrue);
    });

    test('rejects null, traversal, missing slash, other extensions and oversize names', () {
      expect(ArtworkPaths.isSafeTmdbPath(null), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath(''), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath('abc.jpg'), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath('/../abc.jpg'), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath('/a/b.jpg'), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath('/abc.gif'), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath('/abc.jpg?x=1'), isFalse);
      expect(ArtworkPaths.isSafeTmdbPath('/${'a' * 121}.jpg'), isFalse);
    });
  });

  group('itemDirectory', () {
    test('movies and shows get their own tree; seasons and episodes resolve to the show', () {
      expect(paths.itemDirectory(const MediaKey.movie(5)), 'video/movies/5');
      expect(paths.itemDirectory(const MediaKey.show(5)), 'video/shows/5');
      expect(paths.itemDirectory(const MediaKey.season(5, 2)), 'video/shows/5');
      expect(paths.itemDirectory(const MediaKey.episode(5, 2, 3)), 'video/shows/5');
    });
  });

  group('relativePath', () {
    test('uses fixed names per kind, positional numbers, no padding', () {
      expect(paths.relativePath(const ArtworkRef.poster(MediaKey.movie(7), '/p.png')), 'video/movies/7/poster.jpg');
      expect(paths.relativePath(const ArtworkRef.backdrop(MediaKey.movie(7), '/b.jpg')), 'video/movies/7/backdrop.jpg');
      expect(paths.relativePath(const ArtworkRef.poster(MediaKey.show(7), '/p.jpg')), 'video/shows/7/poster.jpg');
      expect(paths.relativePath(const ArtworkRef.backdrop(MediaKey.show(7), '/b.jpg')), 'video/shows/7/backdrop.jpg');
      expect(paths.relativePath(ArtworkRef.seasonPoster(7, 3, '/s.jpg')), 'video/shows/7/seasons/3/poster.jpg');
      expect(paths.relativePath(ArtworkRef.still(7, 3, 12, '/e.jpg')), 'video/shows/7/episodes/3-12/still.jpg');
    });

    test('cast headshots keep the profile basename under the item', () {
      expect(paths.relativePath(const ArtworkRef.cast(MediaKey.movie(7), '/face.jpg')), 'video/movies/7/cast/face.jpg');
      expect(paths.relativePath(const ArtworkRef.cast(MediaKey.show(7), '/Face_1.webp')), 'video/shows/7/cast/Face_1.webp');
    });

    test('a cast ref without a safe path has no file name', () {
      expect(() => paths.relativePath(const ArtworkRef.cast(MediaKey.movie(7), null)), throwsArgumentError);
      expect(() => paths.relativePath(const ArtworkRef.cast(MediaKey.movie(7), '/../x.jpg')), throwsArgumentError);
    });
  });

  test('absolutePath joins under the root and toRelative inverts it', () {
    const relative = 'video/shows/7/seasons/3/poster.jpg';
    final absolute = paths.absolutePath(relative);
    expect(absolute, '/data/app/files/assets/video/shows/7/seasons/3/poster.jpg');
    expect(paths.toRelative(absolute), relative);
  });

  group('candidatePaths', () {
    test('a season poster falls back to the show poster', () {
      expect(paths.candidatePaths(ArtworkRef.seasonPoster(7, 3, '/s.jpg')), [
        'video/shows/7/seasons/3/poster.jpg',
        'video/shows/7/poster.jpg',
      ]);
      expect(paths.candidatePaths(ArtworkRef.seasonPoster(7, 3, null)), ['video/shows/7/seasons/3/poster.jpg', 'video/shows/7/poster.jpg']);
    });

    test('everything else has only its own file', () {
      expect(paths.candidatePaths(const ArtworkRef.poster(MediaKey.movie(7), '/p.jpg')), ['video/movies/7/poster.jpg']);
      expect(paths.candidatePaths(const ArtworkRef.backdrop(MediaKey.show(7), '/b.jpg')), ['video/shows/7/backdrop.jpg']);
      expect(paths.candidatePaths(ArtworkRef.still(7, 1, 1, '/e.jpg')), ['video/shows/7/episodes/1-1/still.jpg']);
      expect(paths.candidatePaths(const ArtworkRef.cast(MediaKey.show(7), '/f.jpg')), ['video/shows/7/cast/f.jpg']);
    });

    test('a cast ref without a safe path has no candidates', () {
      expect(paths.candidatePaths(const ArtworkRef.cast(MediaKey.show(7), null)), isEmpty);
    });
  });

  group('ArtworkRef', () {
    test('fromPosterKey maps a movie or show to its poster and a season or episode to the season poster', () {
      expect(ArtworkRef.fromPosterKey(const MediaKey.movie(1), '/p.jpg'), const ArtworkRef.poster(MediaKey.movie(1), '/p.jpg'));
      expect(ArtworkRef.fromPosterKey(const MediaKey.show(1), '/p.jpg'), const ArtworkRef.poster(MediaKey.show(1), '/p.jpg'));
      expect(ArtworkRef.fromPosterKey(const MediaKey.season(1, 2), '/s.jpg'), ArtworkRef.seasonPoster(1, 2, '/s.jpg'));
      expect(ArtworkRef.fromPosterKey(const MediaKey.episode(1, 2, 3), '/s.jpg'), ArtworkRef.seasonPoster(1, 2, '/s.jpg'));
    });

    test('has value equality and a readable toString', () {
      expect(ArtworkRef.still(1, 2, 3, '/e.jpg'), ArtworkRef.still(1, 2, 3, '/e.jpg'));
      expect(ArtworkRef.still(1, 2, 3, '/e.jpg').hashCode, ArtworkRef.still(1, 2, 3, '/e.jpg').hashCode);
      expect(ArtworkRef.still(1, 2, 3, '/e.jpg'), isNot(ArtworkRef.still(1, 2, 4, '/e.jpg')));
      expect(const ArtworkRef.poster(MediaKey.movie(1), '/p.jpg'), isNot(const ArtworkRef.backdrop(MediaKey.movie(1), '/p.jpg')));
      expect(ArtworkRef.still(1, 2, 3, '/e.jpg').toString(), 'still of show 1 S2E3 (/e.jpg)');
      expect(ArtworkRef.seasonPoster(1, 2, null).toString(), 'season poster of show 1 S2 (null)');
      expect(const ArtworkRef.cast(MediaKey.movie(1), '/f.jpg').toString(), 'cast of movie 1 (/f.jpg)');
    });
  });
}
