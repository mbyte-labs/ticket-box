import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/artwork/artwork_store.dart';
import 'package:ticketbox/service/artwork/asset_download_queue.dart';

/// How a reconcile went: files removed from disk, paths pending afterwards.
typedef ReconcileResult = ({int deleted, int enqueued});

/// Brings one item's directory in line with a fresh [ArtworkManifest]: what the manifest no longer
/// names is deleted (file and queue row), what it names and is missing is queued.
class ArtworkReconciler {
  static final _log = Logger('[Service] ArtworkReconciler');

  final ArtworkStore _store;
  final AssetDownloadQueue _queue;
  final AssetJobRepo _repo;

  ArtworkReconciler({required ArtworkStore store, required AssetDownloadQueue queue, AssetJobRepo? repo})
    : _store = store,
      _queue = queue,
      _repo = repo ?? AssetJobRepo();

  /// Reconciles the whole item behind [manifest]. [resetFailed] gives the rows that failed before
  /// another go — a refresh is the natural moment, the paths may have changed.
  Future<ReconcileResult> reconcile(ArtworkManifest manifest, {bool resetFailed = true}) async {
    final desired = manifest.desiredRelativePaths(_store.paths);
    final onDisk = await _store.listItemFiles(manifest.item);
    var deleted = 0;
    for (final relativePath in onDisk) {
      if (desired.contains(relativePath)) {
        continue;
      }
      await _store.deleteFile(relativePath);
      await _repo.deleteByDestPath(relativePath);
      deleted++;
    }
    await _store.pruneEmptyDirectories(manifest.item);
    final enqueued = await _queue.enqueueManifest(manifest, resetFailed: resetFailed);
    if (deleted > 0 || enqueued > 0) {
      _log.info('Reconciled ${manifest.item}: $deleted file(s) deleted, $enqueued pending');
    }
    return (deleted: deleted, enqueued: enqueued);
  }

  /// Removes everything [item] (a movie or a show) has: its directory and its queue rows.
  Future<void> deleteItemDirectory(MediaKey item) async {
    final owner = item.showKey;
    await _store.deleteItemDirectory(owner);
    await _repo.deleteForItem(owner.type, owner.tmdbId);
    _log.info('Deleted the artwork of $owner');
  }
}
