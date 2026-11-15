/// All the keys used by the SharedPreference storage to save data
class RepositoryKeys {
  /// The database schema version the stored preferences were written against. When it differs
  /// from [DatabaseConnectionManager.currentSchemaVersion], PreferenceVersionGuard removes the
  /// preferences the migration made obsolete (all of them, for a destructive migration).
  static const String appDatabaseVersion = 'repo_database_version';
}
