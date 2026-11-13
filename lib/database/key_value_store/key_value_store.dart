import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class KeyValueStore {
  static final _log = Logger('[Repository] KeyValueStore');

  final SharedPreferencesAsync _store = SharedPreferencesAsync();

  KeyValueStore._();

  static KeyValueStore instance() {
    if (GetIt.I.isRegistered<KeyValueStore>()) {
      return GetIt.I.get<KeyValueStore>();
    }

    _log.info('New instance created');
    final repo = KeyValueStore._();
    GetIt.I.registerSingleton<KeyValueStore>(repo);
    return repo;
  }

  Future<bool> containsKey(String key) async {
    return await _store.containsKey(key);
  }

  Future<void> remove(String key) async {
    _log.fine('Removing property $key');
    await _store.remove(key);
  }

  Future<bool?> getBool(String key) async {
    return await _store.getBool(key);
  }

  Future<bool> getBoolOrDefault(String key, bool defaultValue) async {
    final value = await getBool(key);
    return value ?? defaultValue;
  }

  Future<int?> getInt(String key) async {
    return await _store.getInt(key);
  }

  Future<int> getIntOrDefault(String key, int defaultValue) async {
    final value = await getInt(key);
    return value ?? defaultValue;
  }

  Future<String?> getString(String key) async {
    return await _store.getString(key);
  }

  Future<String> getStringOrDefault(String key, String defaultValue) async {
    final value = await getString(key);
    return value ?? defaultValue;
  }

  Future<List<String>?> getStringList(String key) async {
    return await _store.getStringList(key);
  }

  Future<List<String>> getStringListOrDefault(String key, List<String> defaultValue) async {
    final value = await getStringList(key);
    return value ?? defaultValue;
  }

  Future<T?> getEnum<T>(String key, Iterable<T> values) async {
    final String? value = await getString(key);
    if (value == null) {
      return null;
    }
    return values.firstWhereOrNull((type) => type.toString().split('.').last == value);
  }

  Future<T> getEnumOrDefault<T>(String key, Iterable<T> values, T defaultValue) async {
    final value = await getEnum(key, values);
    return value ?? defaultValue;
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final value = await getString(key);
    if (value == null) {
      return null;
    }
    return json.decode(value);
  }

  Future<void> setString(String key, String value) async {
    await _store.setString(key, value);
  }

  Future<void> setStringList(String key, List<String> value) async {
    await _store.setStringList(key, value);
  }

  Future<void> setInt(String key, int value) async {
    await _store.setInt(key, value);
  }

  Future<void> setBool(String key, bool value) async {
    await _store.setBool(key, value);
  }

  Future<void> setEnum(String key, Enum value) async {
    await _store.setString(key, value.toString().split('.').last);
  }

  Future<void> setJson(String key, Map<String, dynamic> value) async {
    await _store.setString(key, json.encode(value));
  }

  Future<void> setDynamic(String key, dynamic value) async {
    if (value == null) {
      return;
    }

    if (value is String) {
      await setString(key, value);
    }

    if (value is int) {
      await setInt(key, value);
    }

    if (value is bool) {
      await setBool(key, value);
    }

    if (value is List<String>) {
      await setStringList(key, value);
    }

    if (value is Enum) {
      await setString(key, value.toString());
    }
  }

  /// Completes with true once the user preferences for the app has been cleared.
  Future<void> clear() async {
    await _store.clear();
  }
}
