import 'package:flutter/widgets.dart';
import 'package:ticketbox/common/model/poster_size_option.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/constants.dart';

class PosterSizeCalculator {
  static double geAspectRatio(PosterSizeOption posterSize, {double small = 2 / 3.2, double normal = 2 / 3.1}) {
    switch (posterSize) {
      case PosterSizeOption.small:
        return small;
      case PosterSizeOption.normal:
        return normal;
    }
  }

  static double getSize(PosterSizeOption posterSize, [double reduceSizeWith = 0]) {
    switch (posterSize) {
      case PosterSizeOption.small:
        return reduceSizeWith == 0 ? GeneralSizeConstants.smallPoster : ScreenSizeUtil.calculateSize(170 - reduceSizeWith);
      case PosterSizeOption.normal:
        return reduceSizeWith == 0 ? GeneralSizeConstants.normalPoster : ScreenSizeUtil.calculateSize(240 - reduceSizeWith);
    }
  }

  static double getTitleFontSize(PosterSizeOption posterSize, {double small = 12, double normal = 14}) {
    switch (posterSize) {
      case PosterSizeOption.small:
        return small;
      case PosterSizeOption.normal:
        return normal;
    }
  }

  /// Utility method that allows a user to specify margin for something that is
  /// displayed on the poster based on the poster size
  static EdgeInsets getMargin(PosterSizeOption posterSize, {EdgeInsets? small, EdgeInsets? normal}) {
    switch (posterSize) {
      case PosterSizeOption.small:
        return small ?? GeneralMarginConstants.zeroMargin;
      case PosterSizeOption.normal:
        return normal ?? GeneralMarginConstants.zeroMargin;
    }
  }
}
