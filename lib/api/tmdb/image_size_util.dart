import 'package:ticketbox/common/model/poster_quality_option.dart';

class TmdbImageSizeUtil {
  static final _singleton = TmdbImageSizeUtil._internal();
  static const String original = 'original';

  //Poster Sizes
  static const String posterSizeLowest = 'w92';
  static const String posterSizeLow = 'w154';
  static const String posterSizeMedium = 'w185';
  static const String posterSizeMediumPlus = 'w342';
  static const String posterSizeHigh = 'w500';
  static const String posterSizeHighest = 'w780';

  // Logo Sizes
  static const String logoSizeLowest = 'w45';
  static const String logoSizeLow = 'w92';
  static const String logoSizeMedium = 'w154';
  static const String logoSizeMediumPLus = 'w185';
  static const String logoSizeHigh = 'w300';
  static const String logoSizeHighPlus = 'w500';

  // Backdrop Size
  static const String backdropSizeLowest = 'w300';
  static const String backdropSizeMedium = 'w185';
  static const String backdropSizeHighest = 'w780';

  /// The largest fixed backdrop size TMDB serves below `original`; what the library keeps on disk
  /// for a tracked title, whatever the poster quality preference says.
  static const String backdropSizeLarge = 'w1280';

  // profile size
  static const String profileSizeLowest = 'w45';
  static const String profileSizeMedium = 'w185';
  static const String profileSizeHighest = 'w632';

  // still size
  static const String stillSizeLowest = 'w100';
  static const String stillSizeMedium = 'w185';
  static const String stillSizeHighest = 'w300';

  TmdbImageSizeUtil._internal();

  factory TmdbImageSizeUtil() {
    return _singleton;
  }
}

class TmdbImageBuildUtil {
  static const String _baseUrl = 'https://image.tmdb.org/t/';

  static String? buildUrl(String? imagePath, {String imageSize = TmdbImageSizeUtil.original}) {
    if (imagePath == null) {
      return null;
    }
    final buffer = StringBuffer();
    buffer.write(_baseUrl);
    buffer.write('p/');
    buffer.write(imageSize);
    buffer.write(imagePath);

    return buffer.toString();
  }

  static String getPosterImageQuality(PosterQualityOption option) {
    switch (option) {
      case PosterQualityOption.low:
        return TmdbImageSizeUtil.posterSizeLow;
      case PosterQualityOption.medium:
        return TmdbImageSizeUtil.posterSizeMediumPlus;
      case PosterQualityOption.high:
        return TmdbImageSizeUtil.posterSizeHigh;
      case PosterQualityOption.highest:
        return TmdbImageSizeUtil.original;
    }
  }

  /// Actor headshots. These render in a 100px-wide card, so even [PosterQualityOption.low]'s `w45`
  /// is adequate and the top of the scale saturates early.
  static String getProfileImageQuality(PosterQualityOption option) {
    switch (option) {
      case PosterQualityOption.low:
        return TmdbImageSizeUtil.profileSizeLowest;
      case PosterQualityOption.medium:
        return TmdbImageSizeUtil.profileSizeMedium;
      case PosterQualityOption.high:
        return TmdbImageSizeUtil.profileSizeHighest;
      case PosterQualityOption.highest:
        return TmdbImageSizeUtil.original;
    }
  }

  static String getStillImageQuality(PosterQualityOption option) {
    switch (option) {
      case PosterQualityOption.low:
        return TmdbImageSizeUtil.stillSizeMedium;
      case PosterQualityOption.medium:
        return TmdbImageSizeUtil.stillSizeHighest;
      case PosterQualityOption.high:
        return TmdbImageSizeUtil.original;
      case PosterQualityOption.highest:
        return TmdbImageSizeUtil.original;
    }
  }
}
