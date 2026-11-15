import 'package:freezed_annotation/freezed_annotation.dart';

part 'tmdb_auth_models.freezed.dart';
part 'tmdb_auth_models.g.dart';

/// `/3/authentication/token/new`: a request token the user approves on themoviedb.org. Expires 60
/// minutes after it was issued if it is not turned into a session.
@Freezed(toJson: false)
abstract class TmdbRequestToken with _$TmdbRequestToken {
  const factory TmdbRequestToken({
    @Default(false) bool success,
    @JsonKey(name: 'request_token') required String requestToken,
    @JsonKey(name: 'expires_at') String? expiresAt,
  }) = _TmdbRequestToken;

  factory TmdbRequestToken.fromJson(Map<String, dynamic> json) => _$TmdbRequestTokenFromJson(json);
}

/// `/3/authentication/session/new`: the user's session, sent as `session_id` on account calls.
@Freezed(toJson: false)
abstract class TmdbSession with _$TmdbSession {
  const factory TmdbSession({@Default(false) bool success, @JsonKey(name: 'session_id') required String sessionId}) = _TmdbSession;

  factory TmdbSession.fromJson(Map<String, dynamic> json) => _$TmdbSessionFromJson(json);
}

/// TMDB's generic write acknowledgement. `status_code` 1 = created, 12 = updated, 13 = deleted.
@Freezed(toJson: false)
abstract class TmdbStatusResponse with _$TmdbStatusResponse {
  const factory TmdbStatusResponse({
    @JsonKey(name: 'status_code') @Default(0) int statusCode,
    @JsonKey(name: 'status_message') String? statusMessage,
    bool? success,
  }) = _TmdbStatusResponse;

  factory TmdbStatusResponse.fromJson(Map<String, dynamic> json) => _$TmdbStatusResponseFromJson(json);
}
