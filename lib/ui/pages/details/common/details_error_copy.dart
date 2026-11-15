import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';

/// The one wording for the two ways a live details page can fail.
class DetailsErrorCopy {
  const DetailsErrorCopy._();

  static const String notFound = 'This title could not be found on TMDB.';

  static const String unreachable =
      'This title is not in your library yet and TMDB is unreachable — try again when you are online. Your library is unaffected.';

  static const String needsConnection = 'Needs a connection to add this title to your library';

  static String forError(Object error) {
    return switch (classifyJobError(error)) {
      JobErrorCode.networkError || JobErrorCode.serviceDown || JobErrorCode.rateLimited => unreachable,
      _ => 'Loading failed (${error.runtimeType}).',
    };
  }
}
