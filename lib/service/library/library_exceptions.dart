import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';

/// A tracking action on an item that is not in the library yet needed TMDB, and TMDB could not be
/// reached: nothing was written. On a tracked item the same action never touches TMDB.
class TrackingUnavailableException implements Exception {
  final MediaKey key;
  final JobErrorCode code;
  final Object cause;

  const TrackingUnavailableException(this.key, this.code, this.cause);

  @override
  String toString() => 'TrackingUnavailableException($key, ${code.name}): $cause';
}

/// TMDB has no such item (a 404 on an untracked title, or an episode its season does not list).
class ItemGoneException implements Exception {
  final MediaKey key;

  const ItemGoneException(this.key);

  @override
  String toString() => 'ItemGoneException($key)';
}
