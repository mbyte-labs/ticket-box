import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/poster_size_option.dart';
import 'package:ticketbox/ui/routes.dart';

part 'user_details_state.freezed.dart';

@freezed
abstract class UserDetailsState with _$UserDetailsState {
  const factory UserDetailsState({required ApplicationPreferencesState appPreferences}) = _UserSettingsState;

  factory UserDetailsState.initial() {
    return UserDetailsState(appPreferences: ApplicationPreferencesState.initial());
  }
}

@freezed
abstract class ApplicationPreferencesState with _$ApplicationPreferencesState {
  const factory ApplicationPreferencesState({
    required PosterSizeOption posterSize,
    required String defaultLandingPage,
    required int appStartCount,
    required bool isPremium,
  }) = _ApplicationPreferencesState;

  factory ApplicationPreferencesState.initial() {
    return const ApplicationPreferencesState(
      posterSize: PosterSizeOption.normal,
      defaultLandingPage: Routes.upNextToWatch,
      appStartCount: 0,
      isPremium: false,
    );
  }
}
