import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';
import 'package:ticketbox/database/key_value_store/keys/up_next_to_watch_properties_key.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/set_country_banner/set_country_banner_state.dart';

/// Decides whether the up-next dashboard should nudge the user to pick a streaming country.
///
/// The banner shows while [GeneralPropertiesKeys.watchProviderRegion] is unset and the user has
/// not dismissed it. Dismissing is permanent — there is no "fresh start" event left to re-arm it.
class SetCountryBannerBloc extends Cubit<SetCountryBannerState> {
  SetCountryBannerBloc() : super(const SetCountryBannerState());

  /// (Re-)evaluates visibility. Called on page init and again after returning from Settings,
  /// since there is no app-wide change signal for the country preference.
  Future<void> refresh() async {
    final store = KeyValueStore.instance();
    final region = await store.getString(GeneralPropertiesKeys.watchProviderRegion);
    if (region != null) {
      _emitVisible(false);
      return;
    }
    final dismissed = await store.getBoolOrDefault(UpNextToWatchPropertiesKeys.countryBannerDismissed, false);
    _emitVisible(!dismissed);
  }

  Future<void> dismiss() async {
    await KeyValueStore.instance().setBool(UpNextToWatchPropertiesKeys.countryBannerDismissed, true);
    _emitVisible(false);
  }

  void _emitVisible(bool visible) {
    if (isClosed) {
      return;
    }
    emit(state.copyWith(visible: visible));
  }
}
