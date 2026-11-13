import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/common/exception/internal_exception.dart';

/// Represents an exception that was thrown from the API. One that was not expected by the user
class ApiException extends InternalException {
  final ApiProvider apiProvider;
  int statusCode;
  String? responseBody;

  ApiException(this.apiProvider, this.statusCode, this.responseBody, super.message);

  @override
  String toString() {
    return ''' API exception occured:
mesage: $message
StatusCode = $statusCode
Response Body: $responseBody
''';
  }
}

/// Represents an exception that was thrown from the API. One that was not expected by the user
class ApiToManyRequestsException extends ApiException {
  int retryAfter;

  ApiToManyRequestsException(ApiProvider apiProvider, int statusCode, String message, this.retryAfter)
    : super(apiProvider, statusCode, null, message);
}

/// Thrown before a request is even sent, when it needs authentication but no access token is stored.
///
/// Carries status 401 so the sync error classifier's existing `ApiException && 401` branch routes it
/// to "sign in required" without the api layer having to know about service-layer exception types.
class ApiNotAuthenticatedException extends ApiException {
  ApiNotAuthenticatedException(ApiProvider apiProvider, String message) : super(apiProvider, 401, null, message);
}

/// TMDB answered 401. [tmdbStatusCode] is TMDB's own `status_code` from the body: 7 is an invalid
/// API key — a build problem, nothing the user can fix — while 3 and 17 (and anything else) mean
/// the session is missing, revoked or expired, so the user has to log in to TMDB again.
class ApiUnauthorizedException extends ApiException {
  final int? tmdbStatusCode;

  ApiUnauthorizedException(ApiProvider apiProvider, String? responseBody, String message, {this.tmdbStatusCode})
    : super(apiProvider, 401, responseBody, message);

  /// Whether the stored TMDB session is the problem (as opposed to the app's own API key).
  bool get isSessionProblem => tmdbStatusCode != 7;
}

/// Represents an exception that was thrown from the API. One that was not expected by the user
class ApiVipOnlyClientException extends ApiException {
  /// Default constructor
  ApiVipOnlyClientException(super.apiProvider, super.statusCode, super.apiResponse, super.message);
}

/// Represents an exception that was thrown from the API. One that was not expected by the user
class ApiUserLockedException extends ApiException {
  /// Default constructor
  ApiUserLockedException(super.apiProvider, super.statusCode, super.apiResponse, super.message);
}

/// The requested item does not exist (HTTP 404) — a removed or merged TMDB entry.
///
/// Most wrappers return `null` on 404; this exists for callers that must tell "gone" apart from
/// "failed", such as the progress refresh job, which skips a vanished show instead of failing.
class ApiNotFoundException extends ApiException {
  ApiNotFoundException(ApiProvider apiProvider, String? responseBody, String message) : super(apiProvider, 404, responseBody, message);
}

/// Represents an exception that was thrown from the API. One that was not expected by the user
class ApiDownException extends ApiException {
  /// Default constructor
  ApiDownException(super.apiProvider, super.statusCode, super.apiResponse, super.message);
}

class JsonFormatException extends InternalException {
  String apiResponse;

  JsonFormatException(this.apiResponse, [String message = 'Json format exception occured']) : super(message);
}
