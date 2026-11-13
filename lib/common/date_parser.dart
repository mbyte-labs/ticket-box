import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/common/week_parser.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart';

class DateParser {
  static final _log = Logger('[Service] DateParser');
  static final DateParser _singleton = DateParser._internal();

  // Africa/Abidjan has no UTC time offset and neither day light saving
  //static const String _utcTimezone = 'Africa/Abidjan';

  DateParser._internal() {
    _log.finer('creating DateUtil');
    tz.initializeTimeZones();
  }

  factory DateParser() {
    return _singleton;
  }

  /// Returns the UTC time as string. Formatting looks like this: yyyy-MM-ddTHH:mm:ss.mmmuuuZ
  static String currentUtcTimeStampAsString() {
    return DateTime.now().toUtc().toIso8601String();
  }

  static int currentUtcTimeStampAsNumber() {
    return DateTime.now().toUtc().millisecondsSinceEpoch;
  }

  /// Expects that millis are UTC
  static DateTime fromUtcMilliseconds(int milliTime) {
    _log.finest('entering method fromMilliseconds');
    return DateTime.fromMillisecondsSinceEpoch(milliTime, isUtc: true);
  }

  /// yyyy - for complete year: 2021 <br>
  /// MM - for months starting from 01 - 12 <br>
  /// dd - for days starting from 1-31
  static String dateToString(DateTime date, String format) {
    _log.finest('entering method dateToString');
    final DateFormat formatter = DateFormat(format);
    return formatter.format(date);
  }

  static String parseStringAndFormat(String dateTimeStr, String format) {
    _log.finer('entering method parseStringAndFormat');
    final DateTime dateTime = DateTime.parse(dateTimeStr).toLocal();
    return dateToString(dateTime, format);
  }

  static DateTime parseUtcStringToLocalTime(String utcTimeString) {
    _log.finest('entering method parseUtcStringToLocalTime');
    DateTime utcTime = DateTime.parse(utcTimeString);
    return utcTime.toLocal();
  }

  static String printDuration(Duration duration) {
    _log.finest('entering method printDuration');
    String twoDigits(int n) => n.toString();
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    return '${twoDigits(duration.inHours)} hours, $twoDigitMinutes mins';
  }

  static String? getAirDateAndTime(String timezone, String airDay, String airHour, String airMinute) {
    final showTimezone = getLocation(timezone);
    TZDateTime currentTime = TZDateTime.now(showTimezone);
    int dayOfWeekNr = WeekParser.getDayOfWeekFromStr(airDay);
    if (dayOfWeekNr == -1) {
      return null;
    }

    while (currentTime.weekday != dayOfWeekNr) {
      currentTime = currentTime.subtract(const Duration(days: 1));
    }

    TZDateTime time = TZDateTime(
      showTimezone,
      currentTime.year,
      currentTime.month,
      currentTime.day,
      int.parse(airHour),
      int.parse(airMinute),
      currentTime.second,
      currentTime.millisecond,
      currentTime.microsecond,
    );

    return time.toUtc().toIso8601String();
  }

  static String getSimpleDateFormat() {
    Tuple3 dateStyle = getPreferedDateOrder('dd', 'MMM', 'yyyy');
    return '${dateStyle.item1} ${dateStyle.item2} ${dateStyle.item3}';
  }

  static String getHourFormat(final bool use24H) {
    if (true == use24H) {
      return 'HH:mm';
    }

    return 'hh:mm a';
  }

  static Tuple3<String, String, String> getPreferedDateOrder(String day, String month, String year) {
    final dateFormat = _getDateFormat();
    Tuple3<String, String, String> format = Tuple3(day, month, year);
    format = format.copyWith(
      item1: _getDateTypeForPosition(0, dateFormat, day, month, year),
      item2: _getDateTypeForPosition(1, dateFormat, day, month, year),
      item3: _getDateTypeForPosition(2, dateFormat, day, month, year),
    );

    return format;
  }

  /// Position can be any number fro, 0 to 2
  /// Format is a letter order such as `dmy` or any combination of the three
  static String _getDateTypeForPosition(int position, List<String> format, String day, String month, String year) {
    String typeOnPosition = format[position];

    if ('d' == typeOnPosition) {
      return day;
    }

    if ('m' == typeOnPosition) {
      return month;
    }

    if ('y' == typeOnPosition) {
      return year;
    }

    _log.severe('Cannot find date type for position $position and format $format');

    return day;
  }

  static List<String> _getDateFormat() {
    // if (settings != null) {
    //   return settings.account.dateFormat.split("");
    // }
    return 'dmy'.split('');
  }
}

//https://pub.dev/documentation/intl/latest/intl/DateFormat-class.html

//ICU Name                   Skeleton
// --------                   --------
// DAY                          d
// ABBR_WEEKDAY                 E
// WEEKDAY                      EEEE - Monday, Sunday etc
// ABBR_STANDALONE_MONTH        LLL
// STANDALONE_MONTH             LLLL
// NUM_MONTH                    M
// NUM_MONTH_DAY                Md
// NUM_MONTH_WEEKDAY_DAY        MEd
// ABBR_MONTH                   MMM
// ABBR_MONTH_DAY               MMMd
// ABBR_MONTH_WEEKDAY_DAY       MMMEd
// MONTH                        MMMM
// MONTH_DAY                    MMMMd
// MONTH_WEEKDAY_DAY            MMMMEEEEd
// ABBR_QUARTER                 QQQ
// QUARTER                      QQQQ
// YEAR                         y
// YEAR_NUM_MONTH               yM
// YEAR_NUM_MONTH_DAY           yMd
// YEAR_NUM_MONTH_WEEKDAY_DAY   yMEd
// YEAR_ABBR_MONTH              yMMM
// YEAR_ABBR_MONTH_DAY          yMMMd
// YEAR_ABBR_MONTH_WEEKDAY_DAY  yMMMEd
// YEAR_MONTH                   yMMMM
// YEAR_MONTH_DAY               yMMMMd
// YEAR_MONTH_WEEKDAY_DAY       yMMMMEEEEd
// YEAR_ABBR_QUARTER            yQQQ
// YEAR_QUARTER                 yQQQQ
// HOUR24                       H
// HOUR24_MINUTE                Hm
// HOUR24_MINUTE_SECOND         Hms
// HOUR                         j
// HOUR_MINUTE                  jm
// HOUR_MINUTE_SECOND           jms
// HOUR_MINUTE_GENERIC_TZ       jmv
// HOUR_MINUTE_TZ               jmz
// HOUR_GENERIC_TZ              jv
// HOUR_TZ                      jz
// MINUTE                       m
// MINUTE_SECOND                ms
// SECOND                       s
