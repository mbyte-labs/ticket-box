import 'package:json_annotation/json_annotation.dart';

enum HistoryAction {
  @JsonValue('scrobble')
  scrobble,
  @JsonValue('checkin')
  checkin,
  @JsonValue('watch')
  watch,
}

extension HistoryActionExtention on HistoryAction {
  /// The same wording the watch history sections of the details pages use, so that a filter
  /// label and the entry it filters for never disagree.
  String prettyString() => switch (this) {
    HistoryAction.checkin => 'Checked In',
    HistoryAction.scrobble => 'Scrobbled',
    HistoryAction.watch => 'Manual',
  };
}
