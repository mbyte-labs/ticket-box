import 'package:freezed_annotation/freezed_annotation.dart';

/// Which of TMDB's two cast arrays a person came from.
///
/// TMDB returns `cast` and (on the episode credits endpoint) `guest_stars` as separate lists, which
/// is exactly the split the Cast section's two chips render. The same person can appear in both, so
/// this is part of the stored row's identity rather than a derived flag.
enum CastRole {
  @JsonValue('regular')
  regular,
  @JsonValue('guestStar')
  guestStar,
}
