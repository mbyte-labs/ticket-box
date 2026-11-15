import 'package:flutter_test/flutter_test.dart';
import 'package:ticketbox/api/tmdb/image_size_util.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/service/artwork/artwork_kind.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/artwork/artwork_sizes.dart';

void main() {
  test('posters follow the preference but highest stops at w780, never original', () {
    expect(ArtworkSizes.sizeFor(ArtworkKind.poster, PosterQualityOption.low), 'w154');
    expect(ArtworkSizes.sizeFor(ArtworkKind.poster, PosterQualityOption.medium), 'w342');
    expect(ArtworkSizes.sizeFor(ArtworkKind.poster, PosterQualityOption.high), 'w500');
    expect(ArtworkSizes.sizeFor(ArtworkKind.poster, PosterQualityOption.highest), 'w780');
    // The existing helper is untouched: it still says original.
    expect(TmdbImageBuildUtil.getPosterImageQuality(PosterQualityOption.highest), TmdbImageSizeUtil.original);
  });

  test('season posters size like posters', () {
    for (final quality in PosterQualityOption.values) {
      expect(ArtworkSizes.sizeFor(ArtworkKind.seasonPoster, quality), ArtworkSizes.sizeFor(ArtworkKind.poster, quality));
    }
  });

  test('backdrops are always w1280', () {
    for (final quality in PosterQualityOption.values) {
      expect(ArtworkSizes.sizeFor(ArtworkKind.backdrop, quality), 'w1280');
    }
    expect(TmdbImageSizeUtil.backdropSizeLarge, 'w1280');
  });

  test('stills follow the still scale of the preference', () {
    for (final quality in PosterQualityOption.values) {
      expect(ArtworkSizes.sizeFor(ArtworkKind.still, quality), TmdbImageBuildUtil.getStillImageQuality(quality));
    }
  });

  test('cast headshots are always w185', () {
    for (final quality in PosterQualityOption.values) {
      expect(ArtworkSizes.sizeFor(ArtworkKind.cast, quality), 'w185');
    }
  });

  test('url builds the TMDB image URL at the kind size', () {
    expect(
      ArtworkSizes.url(const ArtworkRef.poster(MediaKey.movie(1), '/abc.jpg'), PosterQualityOption.medium),
      'https://image.tmdb.org/t/p/w342/abc.jpg',
    );
    expect(
      ArtworkSizes.url(const ArtworkRef.backdrop(MediaKey.movie(1), '/b.jpg'), PosterQualityOption.low),
      'https://image.tmdb.org/t/p/w1280/b.jpg',
    );
    expect(ArtworkSizes.url(ArtworkRef.still(1, 2, 3, '/e.jpg'), PosterQualityOption.medium), 'https://image.tmdb.org/t/p/w300/e.jpg');
    expect(
      ArtworkSizes.url(const ArtworkRef.cast(MediaKey.show(1), '/f.jpg'), PosterQualityOption.highest),
      'https://image.tmdb.org/t/p/w185/f.jpg',
    );
  });

  test('url is null for a missing or unsafe path', () {
    expect(ArtworkSizes.url(const ArtworkRef.poster(MediaKey.movie(1), null), PosterQualityOption.medium), isNull);
    expect(ArtworkSizes.url(const ArtworkRef.poster(MediaKey.movie(1), '/../x.jpg'), PosterQualityOption.medium), isNull);
    expect(ArtworkSizes.url(const ArtworkRef.poster(MediaKey.movie(1), 'abc.jpg'), PosterQualityOption.medium), isNull);
  });
}
