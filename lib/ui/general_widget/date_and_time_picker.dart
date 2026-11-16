import 'package:material_ui/material_ui.dart';

class DateAndTimePicker {
  /// Create a date picker and after a date is chosen, then it creates a time picker
  Future<DateTime?> dateAndTimePicker(BuildContext context, [DateTime? initialDateTime]) async {
    final initialDate = initialDateTime ?? DateTime.now();
    final selectedDate = await datePicker(context, initialDate);
    if (selectedDate == null) {
      return null;
    }

    TimeOfDay? initialTime;
    if (initialDateTime != null) {
      initialTime = TimeOfDay(hour: selectedDate.hour, minute: selectedDate.minute);
    }

    if (!context.mounted) {
      return null;
    }
    final selectedTime = await timePicker(context, initialTime);

    if (selectedTime == null) {
      return null;
    }

    return DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      selectedTime.hour,
      selectedTime.minute,
      selectedDate.second,
      selectedDate.millisecond,
      selectedDate.microsecond,
    );
  }

  Future<DateTime?> datePicker(BuildContext context, [DateTime? initialDate]) async {
    final initDate = initialDate ?? DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initDate,
      currentDate: initialDate,
      firstDate: DateTime(1950, 1),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked == null) {
      return null;
    }
    return DateTime(
      picked.year,
      picked.month,
      picked.day,
      picked.hour,
      picked.minute,
      picked.second,
      picked.millisecond,
      picked.microsecond,
    );
  }

  Future<TimeOfDay?> timePicker(BuildContext context, TimeOfDay? initialTime) async {
    final initTime = initialTime ?? TimeOfDay.now();
    final TimeOfDay? picked = await showTimePicker(context: context, initialTime: initTime);

    return picked;
  }
}
