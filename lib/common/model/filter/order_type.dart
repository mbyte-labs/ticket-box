import 'package:ticketbox/common/extension/string_extension.dart';

enum OrderType { ascending, descending }

extension OrderTypeExtention on OrderType {
  String convertToString() {
    return toString().split('.').last.toLowerCase().replaceAll('_', ' ');
  }

  String prettyString() {
    return convertToString().capitalize();
  }

  String toDbType() {
    switch (this) {
      case OrderType.ascending:
        return 'ASC';
      case OrderType.descending:
        return 'DESC';
    }
  }
}
