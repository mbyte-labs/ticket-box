import 'package:collection/collection.dart';

extension EnumExtension on Enum {
  String prettyString() {
    return toString().split('.').last.toLowerCase().replaceAll('_', ' ');
  }
}

class EnumUtil {
  static T? fromString<T>(Iterable<T> values, String value) {
    return values.firstWhereOrNull((type) => type.toString() == value);
  }

  static T? fromPrettyString<T>(Iterable<T> values, String value) {
    return values.firstWhereOrNull((type) => (type as Enum).prettyString() == value);
  }
}
