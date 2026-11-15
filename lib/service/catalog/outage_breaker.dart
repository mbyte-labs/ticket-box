import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';

/// The circuit breaker of one refresh tick: [limit] consecutive *systemic* failures (no network,
/// TMDB down, rate limited) abandon fetching until the next tick. A single vanished title or a
/// malformed payload counts nothing.
class OutageBreaker {
  final int limit;
  int _consecutive = 0;
  JobErrorCode _code = JobErrorCode.none;

  OutageBreaker({this.limit = 3});

  bool get tripped => _consecutive >= limit;

  /// The systemic error code that tripped the breaker, or `none`.
  JobErrorCode get code => tripped ? _code : JobErrorCode.none;

  /// Records a failure; true when it was systemic.
  bool record(Object error) {
    final code = classifyJobError(error);
    if (code == JobErrorCode.unknownError) {
      return false;
    }
    _consecutive++;
    _code = code;
    return true;
  }

  void recordSuccess() => _consecutive = 0;
}
