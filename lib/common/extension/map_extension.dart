import 'package:ticketbox/common/exception/internal_error.dart';

extension MapExtension on Map {
  String getAsString(String key) {
    assertKeyHasValue(key);
    return this[key].toString();
  }

  String? getAsOptionalString(String key) {
    if (!containsKey(key)) {
      return null;
    }

    final value = this[key];
    return value?.toString();
  }

  int? getAsOptionalInt(String key, [int? defaultValue]) {
    if (!containsKey(key)) {
      return defaultValue;
    }

    final value = this[key];
    return value as int;
  }

  void assertKeyHasValue(String key) {
    if (!containsKey(key)) {
      throw InternalError('Something went wrong parsing key $key');
    }
  }
}

class MapUtils {
  static final MapUtils _singleton = MapUtils._internal();

  MapUtils._internal();

  factory MapUtils() {
    return _singleton;
  }
}
