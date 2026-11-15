import 'package:flutter/widgets.dart';

/// Convenient class to calculate the correct screen width or height based on device pixel ratio
///
/// Note that the tests are done with a pre established width and height. If you change the emulator please keep in mind to
/// adjust the screen width/height
// Testing screen for phone is a 6.3 inch with resolution 1440 x 3040 and 556 dpi
class ScreenSizeUtil {
  static const double _testedPhoneWidth = 411.42;
  static const double _testedTabletWidth = 844.0;
  static double _testedDevice = _testedPhoneWidth;
  static bool _isTablet = false;
  static double _shortestSize = -1;

  static bool get isTablet => _isTablet;

  static double get shortestSize => _shortestSize;

  static void init(Size deviceSize) {
    initWithShortestSize(deviceSize.shortestSide);
  }

  static void initWithShortestSize(double shortestSize) {
    _shortestSize = shortestSize;

    if (_shortestSize > 600) {
      _isTablet = true;
      _testedDevice = _testedTabletWidth;
    }
  }

  static double calculateSize(double desiredSize) {
    return (_shortestSize * desiredSize) / _testedDevice;
  }

  static EdgeInsets fromLTRB(double left, double top, double right, double bottom) {
    double correctLeft = calculateSize(left);
    double correctTop = calculateSize(top);
    double correctRight = calculateSize(right);
    double correctBottom = calculateSize(bottom);
    return EdgeInsets.fromLTRB(correctLeft, correctTop, correctRight, correctBottom);
  }
}
