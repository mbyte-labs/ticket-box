import 'dart:convert';

import 'package:ticketbox/database/sql_store/cache/cache.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/db_connection_util.dart';

class InternalCacheRepo {
  final DatabaseConnectionManager _connectionManager;

  InternalCacheRepo() : _connectionManager = DatabaseConnectionInitializer.getConnection();

  Future<void> insert(CacheEntity item) async {
    await _connectionManager //
        .into(_connectionManager.caches) //
        .insertOnConflictUpdate(item.toInsertable());
  }

  Future<void> setJsonOrEmpty(String key, Map<String, dynamic>? value) async {
    final jsonData = value == null ? '' : json.encode(value);
    final item = CacheEntity.build(key: key, customData: jsonData, synchronizedAt: DateTime.now().toUtc());

    await delete(key);
    await insert(item);
  }

  Future<void> setJson(String key, Map<String, dynamic> value) async {
    final jsonData = json.encode(value);
    final item = CacheEntity.build(key: key, customData: jsonData, synchronizedAt: DateTime.now().toUtc());

    await delete(key);
    await insert(item);
  }

  Future<CacheEntity?> get(String key) async {
    final query = _connectionManager.select(_connectionManager.caches)..where((cache) => cache.key.equals(key));
    return await query.map((row) => row).getSingleOrNull();
  }

  Future<Map<String, dynamic>?> getJson(String key) async {
    final CacheEntity? value = await get(key);
    if (value == null || value.customData.isEmpty) {
      return null;
    }
    return json.decode(value.customData);
  }

  Future<void> delete(String key) async {
    await (_connectionManager.delete(_connectionManager.caches)..where((cache) => cache.key.equals(key))).go();
  }

  Future<void> deleteAll() async {
    await _connectionManager.delete(_connectionManager.caches).go();
  }
}
