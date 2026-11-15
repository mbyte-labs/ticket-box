import 'package:drift/drift.dart';
import 'package:ticketbox/common/model/history_action_type.dart';

class HistoryActionConverter extends TypeConverter<HistoryAction, String> {
  const HistoryActionConverter();

  @override
  HistoryAction fromSql(String fromDb) {
    return HistoryAction.values.firstWhere((e) => e.toString().split('.').last == fromDb);
  }

  @override
  String toSql(HistoryAction value) {
    return value.toString().split('.').last; // Save as string without "Status."
  }
}
