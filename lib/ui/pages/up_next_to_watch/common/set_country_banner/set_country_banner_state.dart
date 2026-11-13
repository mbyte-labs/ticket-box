import 'package:freezed_annotation/freezed_annotation.dart';

part 'set_country_banner_state.freezed.dart';

@freezed
abstract class SetCountryBannerState with _$SetCountryBannerState {
  const factory SetCountryBannerState({
    /// Whether the "set your country" banner should be on screen. Starts hidden so the
    /// banner never flashes while the async checks in [SetCountryBannerBloc.init] run.
    @Default(false) bool visible,
  }) = _SetCountryBannerState;
}
