import 'dart:async';

import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_reconciler.dart';
import 'package:ticketbox/service/artwork/artwork_resolver.dart';
import 'package:ticketbox/service/artwork/artwork_sizes.dart';
import 'package:ticketbox/service/artwork/artwork_store.dart';
import 'package:ticketbox/service/artwork/asset_download_queue.dart';
import 'package:ticketbox/service/artwork/asset_download_worker.dart';
import 'package:ticketbox/service/artwork/cache/artwork_cache.dart';

/// What the Settings page reports about artwork storage.
typedef ArtworkStorageSummary = ({int assetBytes, int assetFiles, int cacheBytes, int pendingJobs, int failedJobs});

/// The facade the rest of the app talks to about artwork: a title was tracked, refreshed or
/// untracked; drain the queue; report storage.
///
/// Every method is safe when the artwork root could not be resolved at start-up: it logs and
/// does nothing, and the widgets keep rendering through the browse cache. [initialize] wires the
/// singletons (paths, index, store, worker, resolver) and loads the index within a short budget.
class ArtworkService {
  static final _log = Logger('[Service] ArtworkService');

  /// How long start-up waits for the index walk before letting it finish in the background.
  static const Duration indexLoadBudget = Duration(milliseconds: 1500);

  final ArtworkStore? _store;
  final AssetDownloadQueue? _queue;
  final AssetDownloadWorker? _worker;
  final ArtworkReconciler? _reconciler;
  final AssetJobRepo Function() _repo;

  ArtworkService({
    required ArtworkStore store,
    AssetDownloadQueue? queue,
    AssetDownloadWorker? worker,
    ArtworkReconciler? reconciler,
    AssetJobRepo Function()? repo,
  }) : this._(
         store: store,
         queue: queue ?? AssetDownloadQueue(store: store),
         worker: worker ?? AssetDownloadWorker(store: store),
         reconciler: reconciler,
         repo: repo,
       );

  /// The service without an artwork root: every method logs and no-ops.
  ArtworkService.unavailable({AssetJobRepo Function()? repo}) : this._(repo: repo);

  ArtworkService._({
    ArtworkStore? store,
    AssetDownloadQueue? queue,
    AssetDownloadWorker? worker,
    ArtworkReconciler? reconciler,
    AssetJobRepo Function()? repo,
  }) : _store = store,
       _queue = queue,
       _worker = worker,
       _reconciler = reconciler ?? (store != null && queue != null ? ArtworkReconciler(store: store, queue: queue) : null),
       _repo = repo ?? AssetJobRepo.new;

  static ArtworkService instance() {
    if (GetIt.I.isRegistered<ArtworkService>()) {
      return GetIt.I.get<ArtworkService>();
    }
    _log.info('New instance created');
    final service = GetIt.I.isRegistered<ArtworkStore>()
        ? ArtworkService(store: GetIt.I.get<ArtworkStore>(), worker: AssetDownloadWorker.instance())
        : ArtworkService.unavailable();
    GetIt.I.registerSingleton<ArtworkService>(service);
    return service;
  }

  /// Start-up: resolve the root, register the singletons, load the index (within
  /// [indexLoadBudget]; on timeout the walk goes on in the background and tiles that resolve
  /// before it ends fall back to the network). Never throws — without a root the app runs on the
  /// browse cache alone.
  static Future<void> initialize() async {
    try {
      final paths = GetIt.I.isRegistered<ArtworkPaths>() ? GetIt.I.get<ArtworkPaths>() : await ArtworkPaths.resolve();
      if (!GetIt.I.isRegistered<ArtworkPaths>()) {
        GetIt.I.registerSingleton<ArtworkPaths>(paths);
      }
      final index = ArtworkIndex.instance();
      if (!GetIt.I.isRegistered<ArtworkStore>()) {
        GetIt.I.registerSingleton<ArtworkStore>(ArtworkStore(paths, index));
      }
      AssetDownloadWorker.instance();
      final resolver = ArtworkResolver.instance();
      try {
        resolver.setQuality(await ArtworkSizes.preferredQuality());
      } catch (e, stackTrace) {
        _log.warning('Could not read the poster quality preference: $e', e, stackTrace);
      }
      try {
        await index.load(paths).timeout(indexLoadBudget);
      } on TimeoutException {
        _log.info('Artwork index still loading after ${indexLoadBudget.inMilliseconds} ms; continuing in the background');
      }
    } catch (e, stackTrace) {
      _log.severe('Artwork storage is unavailable; running on the browse cache only', e, stackTrace);
    }
    instance();
  }

  bool get isAvailable => _store != null;

  /// A title entered the library: queue its artwork and start downloading.
  Future<void> itemTracked(ArtworkManifest manifest) async {
    final queue = _queue;
    if (queue == null) {
      return _unavailable('itemTracked ${manifest.item}');
    }
    try {
      await queue.enqueueManifest(manifest);
      kick();
    } catch (e, stackTrace) {
      _log.warning('Could not queue the artwork of ${manifest.item}: $e', e, stackTrace);
    }
  }

  /// A tracked title's snapshot was refreshed: drop what it no longer names, queue what is new.
  Future<void> itemRefreshed(ArtworkManifest manifest) async {
    final reconciler = _reconciler;
    if (reconciler == null) {
      return _unavailable('itemRefreshed ${manifest.item}');
    }
    try {
      await reconciler.reconcile(manifest);
      kick();
    } catch (e, stackTrace) {
      _log.warning('Could not reconcile the artwork of ${manifest.item}: $e', e, stackTrace);
    }
  }

  /// A title left the library: remove its directory and its queue rows.
  Future<void> itemUntracked(MediaKey item) async {
    final reconciler = _reconciler;
    if (reconciler == null) {
      return _unavailable('itemUntracked $item');
    }
    try {
      await reconciler.deleteItemDirectory(item);
    } catch (e, stackTrace) {
      _log.warning('Could not delete the artwork of $item: $e', e, stackTrace);
    }
  }

  Future<void> drain() async {
    final worker = _worker;
    if (worker == null) {
      return _unavailable('drain');
    }
    await worker.drain();
  }

  /// Drains the queue after [delay] when anything is pending (launch, resume); no-op otherwise.
  Future<void> drainIfPending({Duration delay = Duration.zero}) async {
    final worker = _worker;
    if (worker == null) {
      return;
    }
    await worker.drainIfPending(delay: delay);
  }

  /// Stops the worker after its in-flight chunk (the app went to the background).
  void pause() => _worker?.pause();

  void kick() {
    final worker = _worker;
    if (worker == null) {
      _unavailable('kick');
      return;
    }
    worker.kick();
  }

  /// Queues every file of [manifests] that failed before and drains — the Settings action.
  Future<void> redownloadMissing(Iterable<ArtworkManifest> manifests) async {
    final queue = _queue;
    final worker = _worker;
    if (queue == null || worker == null) {
      return _unavailable('redownloadMissing');
    }
    for (final manifest in manifests) {
      try {
        await queue.enqueueManifest(manifest, resetFailed: true);
      } catch (e, stackTrace) {
        _log.warning('Could not re-queue the artwork of ${manifest.item}: $e', e, stackTrace);
      }
    }
    await worker.drain();
  }

  Future<ArtworkStorageSummary> storageSummary() async {
    var assets = (bytes: 0, files: 0);
    final store = _store;
    if (store == null) {
      _unavailable('storageSummary');
    } else {
      try {
        assets = await store.usage();
      } catch (e, stackTrace) {
        _log.warning('Could not measure the artwork directory: $e', e, stackTrace);
      }
    }
    var cacheBytes = 0;
    try {
      cacheBytes = await ArtworkCache.sizeBytes();
    } catch (e, stackTrace) {
      _log.warning('Could not measure the browse cache: $e', e, stackTrace);
    }
    var pending = 0;
    var failed = 0;
    try {
      final repo = _repo();
      pending = await repo.countAllPending();
      failed = await repo.countFailed();
    } catch (e, stackTrace) {
      _log.warning('Could not count the artwork queue: $e', e, stackTrace);
    }
    return (assetBytes: assets.bytes, assetFiles: assets.files, cacheBytes: cacheBytes, pendingJobs: pending, failedJobs: failed);
  }

  Future<void> clearBrowseCache() async {
    try {
      await ArtworkCache.clear();
      _log.info('Browse cache cleared');
    } catch (e, stackTrace) {
      _log.warning('Could not clear the browse cache: $e', e, stackTrace);
    }
  }

  void _unavailable(String what) {
    _log.fine('Artwork storage unavailable; ignoring $what');
  }
}
