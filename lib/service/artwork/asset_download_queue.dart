import 'package:logging/logging.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/common/model/asset_job_status.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/service/artwork/artwork_manifest.dart';
import 'package:ticketbox/service/artwork/artwork_sizes.dart';
import 'package:ticketbox/service/artwork/artwork_store.dart';

/// Puts artwork on the download queue — idempotently, so tracking the same title twice, or
/// tracking it again after a reinstall, costs nothing it already has.
class AssetDownloadQueue {
  static final _log = Logger('[Service] AssetDownloadQueue');

  /// Paths looked up per round trip to the database.
  static const int chunkSize = 200;

  final AssetJobRepo _repo;
  final ArtworkStore _store;
  final Future<PosterQualityOption> Function() _quality;

  AssetDownloadQueue({AssetJobRepo? repo, required ArtworkStore store, Future<PosterQualityOption> Function()? quality})
    : _repo = repo ?? AssetJobRepo(),
      _store = store,
      _quality = quality ?? ArtworkSizes.preferredQuality;

  /// Queues [jobs]. A path with no row is inserted `pending`, or straight away `done` when its file
  /// is already on disk (a reinstall, a crash after the rename). A path with a row keeps it:
  /// `done` stays done, `pending` is left alone, `failed` stays failed unless [resetFailed], and
  /// only a changed [NewAssetJob.size] (a new quality preference) re-queues it. Returns how many
  /// of the given paths are pending afterwards.
  Future<int> enqueue(List<NewAssetJob> jobs, {bool resetFailed = false}) async {
    final unique = {for (final job in jobs) job.destPath: job}.values.toList();
    if (unique.isEmpty) {
      return 0;
    }
    final now = DateTime.now();
    var pending = 0;
    for (final chunk in unique.chunked(chunkSize)) {
      final paths = chunk.map((job) => job.destPath);
      final existing = await _repo.getByDestPaths(paths);
      final toPending = <NewAssetJob>[];
      final toDone = <NewAssetJob>[];
      final itemsToReset = <MediaKey>{};
      for (final job in chunk) {
        final row = existing[job.destPath];
        if (row == null) {
          (_store.fileExists(job.destPath) ? toDone : toPending).add(job);
        } else if (row.size != job.size) {
          await _repo.resetForNewSize(job.destPath, size: job.size, sourceUrl: job.sourceUrl);
        } else if (resetFailed && row.status == AssetJobStatus.failed) {
          itemsToReset.add(MediaKey(type: job.mediaType, tmdbId: job.itemId));
        }
      }
      await _repo.insertIgnore(toPending, createdAt: now);
      await _repo.insertIgnore(toDone, createdAt: now, status: AssetJobStatus.done);
      for (final item in itemsToReset) {
        await _repo.resetFailed(item: item);
      }
      final after = await _repo.getByDestPaths(paths);
      pending += after.values.where((row) => row.status == AssetJobStatus.pending).length;
      _log.fine('Queued ${toPending.length} new, ${toDone.length} already on disk, ${itemsToReset.length} item(s) reset');
    }
    return pending;
  }

  /// [enqueue] for everything [manifest] wants, at the current quality preference.
  Future<int> enqueueManifest(ArtworkManifest manifest, {bool resetFailed = false}) async {
    final quality = await _quality();
    return enqueue(manifest.toJobs(_store.paths, quality), resetFailed: resetFailed);
  }
}
