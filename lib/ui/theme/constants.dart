import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';

class GeneralMarginConstants {
  static const zeroMargin = EdgeInsets.fromLTRB(0, 0, 0, 0);
}

class GeneralSizeConstants {
  static final smallPoster = ScreenSizeUtil.calculateSize(170);
  static final normalPoster = ScreenSizeUtil.calculateSize(240);
}

class PosterConstants {
  static const aspectRationWhenNoTitle = 2 / 3;
  static const aspectRationWhenTitle = 2 / 2.8;
  static const aspectRationWhenTitleAndSubtitle = 2 / 2.68;

  /// Landscape ratio for episode stills, which TMDB serves as 16:9.
  static const stillAspectRatio = 16 / 9;
  static final titleMargin = ScreenSizeUtil.fromLTRB(2, 5, 2, 0);
  static final subTitleMargin = ScreenSizeUtil.fromLTRB(2, 0, 2, 0);

  static const noPosterMargin = EdgeInsets.fromLTRB(0, 0, 0, 0);
  static final imageErrorMargin = ScreenSizeUtil.fromLTRB(5, 0, 5, 0);
}

/// Holds constants used by the SliverGrid where the posters reside on a page
class PosterPageConstants {
  static final padding = ScreenSizeUtil.fromLTRB(5, 10, 5, 0);
}
