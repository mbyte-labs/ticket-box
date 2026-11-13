import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/database/repository_exception.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';

class DatabaseConnectionInitializer {
  static final _log = Logger('DatabaseConnectionInitializer');

  static DatabaseConnectionManager getConnection() {
    return GetIt.instance.get<DatabaseConnectionManager>();
  }

  static void initialize() {
    try {
      if (!GetIt.I.isRegistered<DatabaseConnectionManager>()) {
        GetIt.I.registerSingleton<DatabaseConnectionManager>(DatabaseConnectionManager());
      }
    } on RepositoryException catch (e, stacktrace) {
      _log.severe('Error setting up repository', e, stacktrace);
      rethrow;
    }
  }
}
