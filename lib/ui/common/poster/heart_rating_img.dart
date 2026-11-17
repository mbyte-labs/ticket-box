import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/assets_path.dart';

class HeartWidgetUtil {
  static Widget fullImage(Color color, double height, double width) {
    return Image.asset(
      AssetsPath.heartImage,
      height: ScreenSizeUtil.calculateSize(height),
      width: ScreenSizeUtil.calculateSize(width),
      color: color,
    );
  }

  static Widget halfImage(Color color, double height, double width) {
    return Image.asset(
      AssetsPath.heartHalfImage,
      height: ScreenSizeUtil.calculateSize(height),
      width: ScreenSizeUtil.calculateSize(width),
      color: color,
    );
  }

  static Widget emptyImage(Color color, double height, double width) {
    return Image.asset(
      AssetsPath.heartBorderImage,
      height: ScreenSizeUtil.calculateSize(height),
      width: ScreenSizeUtil.calculateSize(width),
      color: color,
    );
  }
}
