extension StringExtension on String {
  String capitalize() {
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  String get capitalizeFirstofEach => split(' ').map((str) => str.capitalize).join(' ');
}

class StringUtils {
  static String capitalize(String str) {
    return str.capitalize();
  }
}
