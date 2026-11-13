import 'package:ticketbox/api/api_provider.dart';
import 'package:ticketbox/common/exception/internal_error.dart';

class ApiError extends InternalError {
  ApiError(super.message);
}

/// Represents an exception that was thrown from the API. One that was not expected by the user
class ApiClientError extends ApiError {
  final ApiProvider apiProvider;

  ApiClientError(this.apiProvider, super.message);
}
