import 'dart:async';
import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:http/http.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/api/http/image_download_client.dart';
import 'package:ticketbox/common/extension/list_extension.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_entity.dart';
import 'package:ticketbox/database/sql_store/asset_job/asset_job_repository.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';
import 'package:ticketbox/service/artwork/artwork_index.dart';
import 'package:ticketbox/service/artwork/artwork_store.dart';
import 'package:ticketbox/service/artwork/cache/artwork_cache.dart';
import 'package:ticketbox/service/artwork/rate_gate.dart';

/// Drains the artwork download queue: every pending row is fetched, in id order, a few at a time.
///
/// Never throws and joins a drain already in flight. A file already in the browse cache is
/// promoted (copied) without a request. A 404 fails the row for good and marks the path missing;
/// a failure of the row's own (a non-image body, a short body, an unexpected status) is retried
/// with a growing back-off and given up after [maxAttempts], and [breakerThreshold] of them in a
/// row stop the drain. When the CDN is unreachable (no network, a timeout, 429, 5xx) the rows in
/// flight are stamped for a retry in a minute and the drain stops, keeping everything for the
/// next launch or resume. A full disk stops it too, with the rows left pending. Progress lands on
/// the `JobStates` row [ARTWORK_DOWNLOAD_JOB_ID].
class AssetDownloadWorker {
  static final _log = Logger('[Service] AssetDownloadWorker');

  /// Downloads in flight at once.
  static const int concurrency = 4;

  /// Rows read per round trip to the database.
  static const int batchSize = 50;

  /// A row still failing after this many attempts is given up on.
  static const int maxAttempts = 5;

  /// Consecutive own failures that stop a drain: something systematic is wrong, not one file.
  static const int breakerThreshold = 10;

  /// How long [drainIfPending] waits after launch before touching the network.
  static const Duration launchDelay = Duration(seconds: 2);

  /// How long an unreachable CDN parks the rows in flight.
  static const Duration unreachableRetryDelay = Duration(minutes: 1);

  static const List<Duration> _backoff = [Duration(minutes: 1), Duration(minutes: 10), Duration(hours: 1), Duration(hours: 6)];

  /// `ENOSPC`.
  static const int _diskFullErrorCode = 28;

  final AssetJobRepo _repo;
  final ArtworkStore _store;
  final ArtworkIndex _index;
  final Client _client;
  final RateGate _gate;
  final Future<File?> Function(String url) _cacheLookup;
  final JobStateRepo _jobs;

  Future<void>? _inFlight;
  bool _pauseRequested = false;

  AssetDownloadWorker({
    AssetJobRepo? repo,
    required ArtworkStore store,
    ArtworkIndex? index,
    Client? client,
    RateGate? gate,
    Future<File?> Function(String url)? cacheLookup,
    JobStateRepo? jobStateRepo,
  }) : _repo = repo ?? AssetJobRepo(),
       _store = store,
       _index = index ?? store.index,
       _client = client ?? ImageDownloadClient.instance,
       _gate = gate ?? RateGate(),
       _cacheLookup = cacheLookup ?? ArtworkCache.lookup,
       _jobs = jobStateRepo ?? JobStateRepo();

  /// The process-wide worker over the registered [ArtworkStore]; `ArtworkService.initialize`
  /// registers that first.
  static AssetDownloadWorker instance() {
    if (GetIt.I.isRegistered<AssetDownloadWorker>()) {
      return GetIt.I.get<AssetDownloadWorker>();
    }
    _log.info('New instance created');
    final worker = AssetDownloadWorker(store: GetIt.I.get<ArtworkStore>());
    GetIt.I.registerSingleton<AssetDownloadWorker>(worker);
    return worker;
  }

  /// Downloads everything that is due, joining a drain already running instead of starting another.
  Future<void> drain() {
    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<void> run;
    run = _drain().whenComplete(() {
      if (_inFlight == run) {
        _inFlight = null;
        _pauseRequested = false;
      }
    });
    _inFlight = run;
    return run;
  }

  /// [drain], after [delay] and only when something is due — for launch and resume, where an
  /// empty queue is the common case and the first seconds belong to the UI.
  Future<void> drainIfPending({Duration delay = launchDelay}) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    try {
      if (await _repo.countPending(now: DateTime.now()) == 0) {
        return;
      }
    } catch (e, stackTrace) {
      _log.warning('Could not read the artwork queue: $e', e, stackTrace);
      return;
    }
    await drain();
  }

  void kick() {
    unawaited(drain());
  }

  /// Stops the drain in flight after its current chunk; the rows stay pending for the next one.
  void pause() {
    if (_inFlight != null) {
      _pauseRequested = true;
    }
  }

  Future<void> _drain() async {
    try {
      await _store.sweepPartFiles();
      final due = await _repo.countPending(now: DateTime.now());
      if (due == 0) {
        return;
      }
      await _markStart(due);
      var errorCode = JobErrorCode.unknownError;
      try {
        errorCode = await _run();
      } finally {
        await _markFinished(errorCode);
      }
    } catch (e, stackTrace) {
      _log.severe('Draining the artwork queue failed', e, stackTrace);
    }
  }

  Future<JobErrorCode> _run() async {
    var afterId = 0;
    var stored = 0;
    var promoted = 0;
    var failed = 0;
    var consecutiveFailures = 0;
    var stop = false;
    var errorCode = JobErrorCode.none;
    while (!stop && !_pauseRequested) {
      final rows = await _repo.getPending(batchSize, afterId: afterId, now: DateTime.now());
      if (rows.isEmpty) {
        break;
      }
      afterId = rows.last.id;
      for (final chunk in rows.chunked(concurrency)) {
        if (_pauseRequested) {
          break;
        }
        final outcomes = await Future.wait(chunk.map(_fetchOne));
        for (var i = 0; i < chunk.length; i++) {
          final row = chunk[i];
          switch (outcomes[i]) {
            case _Stored(:final replaced, promoted: final wasPromoted):
              await _repo.markDone(row.id);
              _index.add(row.destPath, replaced: replaced);
              wasPromoted ? promoted++ : stored++;
              consecutiveFailures = 0;
            case _NotFound():
              await _repo.markFailed(row.id, 'notFound');
              _index.markMissing(row.destPath);
              failed++;
            case _FailedOnce(:final reason):
              failed++;
              consecutiveFailures++;
              if (row.attempts + 1 >= maxAttempts) {
                _log.warning('Giving up on ${row.destPath} after $maxAttempts attempts: $reason');
                await _repo.markFailed(row.id, reason);
              } else {
                await _repo.markRetry(row.id, reason, DateTime.now().add(_backoff[row.attempts.clamp(0, _backoff.length - 1)]));
              }
              if (consecutiveFailures >= breakerThreshold) {
                _log.warning('$consecutiveFailures artwork downloads failed in a row; stopping this drain');
                stop = true;
              }
            case _Unreachable(:final reason, :final code):
              await _repo.markRetry(row.id, reason, DateTime.now().add(unreachableRetryDelay));
              errorCode = code;
              stop = true;
            case _DiskFull(:final reason):
              if (!stop) {
                _log.severe('No space left for artwork ($reason); stopping this drain');
              }
              errorCode = JobErrorCode.unknownError;
              stop = true;
          }
        }
        if (stop) {
          break;
        }
      }
      if (stop) {
        if (errorCode != JobErrorCode.none) {
          _log.info('Image CDN unreachable (${errorCode.name}); keeping the artwork queue for a later drain');
        }
        break;
      }
      await _jobs.updateMessage(ARTWORK_DOWNLOAD_JOB_ID, _message(await _repo.countPending(now: DateTime.now())));
    }
    _log.info('Artwork drain: stored $stored, promoted $promoted, failed $failed${_pauseRequested ? ', paused' : ''}');
    return errorCode;
  }

  Future<_FetchOutcome> _fetchOne(AssetJobEntity row) async {
    try {
      final cached = await _cacheLookup(row.sourceUrl);
      if (cached != null && await cached.exists()) {
        final replaced = await _store.copyAtomically(cached, row.destPath);
        return _Stored(replaced: replaced, promoted: true);
      }

      await _gate.acquire();
      final response = await _client.send(Request('GET', Uri.parse(row.sourceUrl)));
      final status = response.statusCode;
      if (status != 200) {
        await _discard(response);
        if (status == 404) {
          return const _NotFound();
        }
        if (status == 429) {
          return const _Unreachable('rateLimited', JobErrorCode.rateLimited);
        }
        if (status >= 500) {
          return _Unreachable('http $status', JobErrorCode.serviceDown);
        }
        return _FailedOnce('http $status');
      }
      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().startsWith('image/')) {
        await _discard(response);
        return _FailedOnce('not an image: ${contentType.isEmpty ? 'no content type' : contentType}');
      }
      final (_, replaced) = await _store.writeAtomically(row.destPath, response.stream, expectedLength: response.contentLength);
      return _Stored(replaced: replaced, promoted: false);
    } on ArtworkWriteException catch (e) {
      return _FailedOnce(e.message);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == _diskFullErrorCode) {
        return _DiskFull(e.message);
      }
      _log.warning('Could not store ${row.destPath}: $e');
      return _FailedOnce('io: ${e.message}');
    } on SocketException catch (e) {
      return _Unreachable('network: ${e.message}', JobErrorCode.networkError);
    } on ClientException catch (e) {
      return _Unreachable('network: ${e.message}', JobErrorCode.networkError);
    } on TimeoutException {
      return const _Unreachable('timeout', JobErrorCode.networkError);
    } catch (e, stackTrace) {
      _log.warning('Could not fetch ${row.sourceUrl}: $e', e, stackTrace);
      return _FailedOnce('$e');
    }
  }

  /// Lets go of a response body that is not wanted, so the connection can be reused.
  static Future<void> _discard(StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } catch (e) {
      _log.fine('Discarding a response body failed: $e');
    }
  }

  static String _message(int left) => 'Downloading artwork ($left left)…';

  Future<void> _markStart(int due) async {
    final job = await _jobs.get(ARTWORK_DOWNLOAD_JOB_ID);
    job.startedAt = DateTime.now();
    job.state = JobState.running;
    job.errorCode = JobErrorCode.none;
    job.userMessage = _message(due);
    await _jobs.insert(job);
  }

  Future<void> _markFinished(JobErrorCode errorCode) async {
    final job = await _jobs.get(ARTWORK_DOWNLOAD_JOB_ID);
    job.errorCode = errorCode;
    if (errorCode == JobErrorCode.none) {
      job.state = JobState.finished;
      job.finishedAt = DateTime.now();
    } else {
      job.state = JobState.failed;
    }
    job.userMessage = null;
    await _jobs.insert(job);
  }
}

sealed class _FetchOutcome {
  const _FetchOutcome();
}

class _Stored extends _FetchOutcome {
  final bool replaced;
  final bool promoted;

  const _Stored({required this.replaced, required this.promoted});
}

class _NotFound extends _FetchOutcome {
  const _NotFound();
}

class _FailedOnce extends _FetchOutcome {
  final String reason;

  const _FailedOnce(this.reason);
}

class _Unreachable extends _FetchOutcome {
  final String reason;
  final JobErrorCode code;

  const _Unreachable(this.reason, this.code);
}

class _DiskFull extends _FetchOutcome {
  final String reason;

  const _DiskFull(this.reason);
}
