// set the converter device dimensions here for mobile / tablet / desktop

/// Specifies the form factor of the device.
///
/// This dimensions represent the smallest width of the device screen
enum FormFactor implements Comparable<FormFactor> {
  mobile(width: 300),
  tablet(width: 900),
  desktop(width: 1320);

  const FormFactor({required this.width});

  final double width;

  /// TODO: This needs to be created in another way
  bool get isTouchEnabled => this == FormFactor.mobile || this == FormFactor.tablet;

  @override
  int compareTo(FormFactor other) {
    if (width < other.width) {
      return -1;
    } else if (width == other.width) {
      return 0;
    } else if (width > other.width) {
      return 1;
    }
    return 1;
  }
}
