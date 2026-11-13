import 'dart:io';

import 'package:drift/native.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:ticketbox/api/http/image_download_client.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_entity.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/database/sql_store/database_connection_manager.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_reconciler.dart';
import 'package:ticketbox/service/artwork/artwork_store.dart';
import 'package:ticketbox/service/artwork/asset_download_queue.dart';
import 'package:ticketbox/service/artwork/asset_download_worker.dart';
import 'package:ticketbox/service/artwork/rate_gate.dart';

/// The fixture the artwork tests share: a temporary artwork root, an in-memory database, a mock
/// transport behind [ImageDownloadClient], an unlimited rate gate and a stubbed browse cache.
class ArtworkTestHarness {
  /// Any non-empty bytes pass for a JPEG: nothing here decodes them.
  static const List<int> jpegBytes = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 6, 7, 8];

  late Directory tempDir;
  late ArtworkPaths paths;
  late DatabaseConnectionManager db;
  late ArtworkIndex index;
  late ArtworkStore store;
  late AssetJobRepo repo;
  late JobStateRepo jobStates;

  /// Every request the mock transport saw, in order (retries included).
  final List<Request> requests = [];

  /// What the browse-cache lookup stub answers, by URL.
  final Map<String, File> cacheFiles = {};

  /// The mock transport's answer; replaceable per test, reset by [setUp].
  Future<Response> Function(Request request) handler = _defaultHandler;

  int _cacheFileCounter = 0;

  Future<void> setUp({Future<Response> Function(Request request)? handler, Client? client}) async {
    requests.clear();
    cacheFiles.clear();
    this.handler = handler ?? _defaultHandler;
    tempDir = await Directory.systemTemp.createTemp('artwork');
    paths = ArtworkPaths(p.join(tempDir.path, 'assets'));
    db = DatabaseConnectionManager.forTesting(NativeDatabase.memory());
    GetIt.I.registerSingleton<DatabaseConnectionManager>(db);
    GetIt.I.registerSingleton<ArtworkPaths>(paths);
    index = ArtworkIndex.instance();
    store = ArtworkStore(paths, index);
    GetIt.I.registerSingleton<ArtworkStore>(store);
    repo = AssetJobRepo();
    jobStates = JobStateRepo();
    ImageDownloadClient.forTesting(
      client ??
          MockClient((request) {
            requests.add(request);
            return this.handler(request);
          }),
    );
  }

  Future<void> tearDown() async {
    ImageDownloadClient.resetForTesting();
    await GetIt.I.reset();
    await db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  }

  AssetDownloadQueue queue({PosterQualityOption quality = PosterQualityOption.medium}) =>
      AssetDownloadQueue(repo: repo, store: store, quality: () async => quality);

  AssetDownloadWorker worker() => AssetDownloadWorker(
    repo: repo,
    store: store,
    index: index,
    client: ImageDownloadClient.instance,
    gate: RateGate.unlimited(),
    cacheLookup: (url) async => cacheFiles[url],
    jobStateRepo: jobStates,
  );

  ArtworkReconciler reconciler() => ArtworkReconciler(store: store, queue: queue(), repo: repo);

  /// Every queue row, by id.
  Future<List<AssetJobEntity>> rows() async => (await db.select(db.assetJobs).get())..sort((a, b) => a.id.compareTo(b.id));

  File file(String relativePath) => File(paths.absolutePath(relativePath));

  /// Writes an artwork file straight to disk, as a previous install would have left it.
  Future<File> writeFile(String relativePath, [List<int> bytes = jpegBytes]) async {
    final target = file(relativePath);
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
    return target;
  }

  /// Puts a file in the stubbed browse cache under [url].
  Future<File> writeCached(String url, [List<int> bytes = jpegBytes]) async {
    final target = File(p.join(tempDir.path, 'cache', '${_cacheFileCounter++}.bin'));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes);
    cacheFiles[url] = target;
    return target;
  }

  /// Everything under the artwork root, `.part` files included, as relative paths.
  Future<List<String>> filesOnDisk() async {
    final root = Directory(paths.assetsRoot);
    if (!await root.exists()) {
      return const [];
    }
    final files = <String>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        files.add(paths.toRelative(entity.path));
      }
    }
    return files..sort();
  }

  static Future<Response> _defaultHandler(Request request) async => jpeg();

  static Response jpeg([List<int> bytes = jpegBytes]) => Response.bytes(bytes, 200, headers: {'content-type': 'image/jpeg'});

  static Response html() => Response('<html><body>not an image</body></html>', 200, headers: {'content-type': 'text/html'});

  static Response status(int code) => Response('', code);
}
