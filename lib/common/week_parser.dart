import 'package:logging/logging.dart';

class WeekParser {
  static final _log = Logger('[Service] WeekParser');
  static final WeekParser _singleton = WeekParser._internal();

  WeekParser._internal() {
    _log.finer('creating WeekUtil');
  }

  factory WeekParser() {
    return _singleton;
  }

  static int getDayOfWeekFromStr(String dayOfWeek) {
    _log.finest('entering method getDayOfWeekFromStr');

    switch (dayOfWeek.toLowerCase()) {
      case 'monday':
        return DateTime.monday;
      case 'tuesday':
        return DateTime.tuesday;
      case 'wednesday':
        return DateTime.wednesday;
      case 'thursday':
        return DateTime.thursday;
      case 'friday':
        return DateTime.friday;
      case 'saturday':
        return DateTime.saturday;
      case 'sunday':
        return DateTime.sunday;
    }
    _log.warning('exiting method getDayOfWeekFromStr | returns -1. input data: $dayOfWeek');
    return -1;
  }

  static String? getDayOfWeek(int dayOfWeek) {
    _log.finest('entering method getDayOfWeek');
    switch (dayOfWeek) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
    }
    _log.warning('exiting method getDayOfWeek | returns null. inpunt data: $dayOfWeek');
    return null;
  }
}
