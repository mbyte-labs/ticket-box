enum JobErrorCode {
  none,

  /// An exception was raised that no handler recognises
  unknownError,

  /// The request never reached the service — no connectivity, DNS failure, connection reset or
  /// timeout. "Check your internet connection" is the useful advice and retrying is safe.
  networkError,

  /// TMDB answered with a 5xx: the problem is on their side, try again later.
  serviceDown,

  /// TMDB refused further requests. Nothing is broken; retrying immediately makes it worse.
  rateLimited,
}
