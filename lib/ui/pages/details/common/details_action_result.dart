import 'package:ticketbox/service/library/library_exceptions.dart';

/// How an action-bar write ended, so the page can say why when it did not happen.
enum DetailsActionResult {
  done,

  /// The title is not in the library yet and TMDB could not be reached to add it.
  needsConnection,

  /// TMDB has no such title any more.
  gone,
  failed;

  bool get succeeded => this == DetailsActionResult.done;

  static DetailsActionResult forError(Object error) {
    if (error is TrackingUnavailableException) {
      return DetailsActionResult.needsConnection;
    }
    if (error is ItemGoneException) {
      return DetailsActionResult.gone;
    }
    return DetailsActionResult.failed;
  }

  /// The snackbar for a failed [fallback] action, or null when it succeeded.
  String? message(String fallback) {
    return switch (this) {
      DetailsActionResult.done => null,
      DetailsActionResult.needsConnection => 'Needs a connection to add this title to your library',
      DetailsActionResult.gone => 'This title no longer exists on TMDB',
      DetailsActionResult.failed => fallback,
    };
  }
}
