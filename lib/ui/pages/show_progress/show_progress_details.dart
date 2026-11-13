import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/service/poster/poster_model.dart';

part 'show_progress_details.freezed.dart';

/// One tracked show on the Show Progress page, ready to render.
@freezed
abstract class ShowProgressRowDetails with _$ShowProgressRowDetails {
  const ShowProgressRowDetails._();

  const factory ShowProgressRowDetails({
    required int showTmdbId,
    required String title,

    /// The show's marked poster tile; a show without a catalogue snapshot yet renders its title
    /// card instead of artwork.
    required PosterModel poster,
    required int aired,
    required int completed,
    required LastWatchedEpisode? lastWatched,
  }) = _ShowProgressRowDetails;

  /// Watched fraction, guarded against progress rows synced before the show summary (aired == 0).
  double get progress => aired == 0 ? 0 : (completed / aired).clamp(0, 1).toDouble();
}

/// The most recently watched episode of a show.
@freezed
abstract class LastWatchedEpisode with _$LastWatchedEpisode {
  const LastWatchedEpisode._();

  const factory LastWatchedEpisode({
    required int season,
    required int episode,

    /// Null when the episode row has not been synchronized yet - the label degrades to `19x20`.
    required String? title,
    required DateTime watchedAt,
  }) = _LastWatchedEpisode;

  /// `19x20 Happily Ever After?`, or just `19x20` when the title is unknown.
  String get label {
    final numbers = '${season}x$episode';
    return title == null || title!.isEmpty ? numbers : '$numbers $title';
  }
}

/// One season inside a show's expanded details.
@freezed
abstract class SeasonProgressDetails with _$SeasonProgressDetails {
  const SeasonProgressDetails._();

  const factory SeasonProgressDetails({
    required int season,
    required int aired,
    required int completed,
    required List<EpisodeProgressDetails> episodes,
  }) = _SeasonProgressDetails;

  /// Watched fraction, guarded against a season with no aired episodes.
  double get progress => aired == 0 ? 0 : (completed / aired).clamp(0, 1).toDouble();
}

/// One episode chip inside an expanded season.
@freezed
abstract class EpisodeProgressDetails with _$EpisodeProgressDetails {
  const EpisodeProgressDetails._();

  const factory EpisodeProgressDetails({required int season, required int episode, required bool completed}) = _EpisodeProgressDetails;

  /// `6x1`
  String get label => '${season}x$episode';
}
