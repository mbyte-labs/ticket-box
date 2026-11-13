import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';

/// The country the user picked for streaming availability — the one region a stored snapshot's
/// `watch/providers` is pruned to. Null until the user picks one in Settings.
class WatchRegion {
  const WatchRegion._();

  static Future<String?> configured() async {
    final region = await KeyValueStore.instance().getString(GeneralPropertiesKeys.watchProviderRegion);
    return (region == null || region.isEmpty) ? null : region;
  }
}
