import 'dart:async';

import 'package:http/http.dart';
import 'package:ticketbox/api/exception.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';

/// Maps a thrown error onto the [JobErrorCode] persisted on a job's status row.
JobErrorCode classifyJobError(Object error) {
  // These extend ApiException, so they have to be checked before the generic branch.
  if (error is ApiToManyRequestsException) {
    return JobErrorCode.rateLimited;
  }
  if (error is ApiDownException) {
    return JobErrorCode.serviceDown;
  }
  // The request never got an answer: ClientException wraps socket/DNS failures on IO platforms,
  // TimeoutException comes from the per-attempt cap in TmdbHttpClient.
  if (error is ClientException || error is TimeoutException) {
    return JobErrorCode.networkError;
  }
  return JobErrorCode.unknownError;
}
