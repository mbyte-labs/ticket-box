import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/item_type.dart';

class ItemTypeConverter extends TypeConverter<ItemType, String> {
  const ItemTypeConverter();

  @override
  ItemType fromSql(String fromDb) {
    return ItemType.values.firstWhere((e) => e.toString().split('.').last == fromDb);
  }

  @override
  String toSql(ItemType value) {
    return value.toString().split('.').last; // Save as string without "Status."
  }
}
