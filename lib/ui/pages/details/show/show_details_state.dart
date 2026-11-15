import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_ref.dart';
import 'package:ticketbox/common/model/show_status.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_status.dart';

part 'show_details_state.freezed.dart';

@freezed
abstract class ShowDetailsState with _$ShowDetailsState {
  const factory ShowDetailsState({
    /// The show's TMDB id
    required int providerId,

    /// IMDb id, for the external link. Null until the show has loaded or when TMDB has none.
    required String? imdbId,

    /// The action bar write currently in flight, if any.
    required DetailsPendingAction? pendingAction,
    required bool initialLoading,

    /// Loaded from the snapshot or live, or why not; the page renders [message] for the two
    /// failure values.
    required DetailsLoadStatus loadStatus,
    required bool hasError,
    required String message,

    /// Whether the show is in the library: its artwork is on disk and every action is local.
    required bool tracked,

    /// TMDB relative paths; the artwork layer resolves them.
    required String? posterPath,
    required String? backdropPath,
    required String? title,
    required int? year,
    required String? overview,
    required DateTime? firstAired,

    /// TMDB popularity score and vote count, shown in the "On TMDB" card. Null until loaded.
    required double? popularity,
    required int? voteCount,

    /// TMDB and IMDb community ratings for the second row of the Ratings card.
    /// Null until the first (cached or fresh) answer arrives.
    required ExternalRatings? externalRatings,

    /// The network that airs the show
    required String? network,
    required String? country,
    required String? certification,
    required ShowStatus status,
    required String? language,
    required List<String> genres,

    /// Runtime of a single episode, in minutes
    required int? runtime,

    /// Number of episodes that have already aired across every season
    required int airedEpisodes,

    /// When the next episode airs, if TMDB has announced one
    required DateTime? nextEpisodeAirDate,
    required String? trailer,
    required String? homepage,

    /// How many episodes of this show the user has watched, from the synced watch progress
    required int watchedEpisodes,
    required DateTime? lastWatchedAt,
    required String? userRating,
    required bool watchListed,
    required bool dropped,
    required bool favorite,

    /// One tile per season, ordered by season number, marked with the user's rows.
    required List<PosterModel> seasons,
    required List<CastMember> actorsRegulars,
    required List<CastMember> actorsGuests,
    required List<DetailsExternalLink> externalLinks,

    /// Watch history entries for every episode of this show, newest first
    required List<ShowWatchEntry> watchedHistory,

    /// The shows TMDB recommends alongside this one, most relevant first, from the snapshot.
    required List<PosterModel> related,

    /// Whether the user has picked a streaming country in the settings. While false the
    /// Watch now section renders nothing — the "set your country" nudge lives on the up-next
    /// dashboard instead.
    required bool watchProviderRegionSet,

    /// Subscription services streaming this show in the user's country, most relevant first.
    /// Empty when nothing has loaded yet or the show has no streaming offer there.
    required List<DetailsWatchProvider> watchProviders,

    /// JustWatch offer page for this show in the user's country, opened by tapping any provider logo.
    /// Null when TMDB has no offer link, which leaves the logos inert.
    String? watchProviderLink,
  }) = _ShowDetailsState;

  factory ShowDetailsState.initial(int providerId) {
    return ShowDetailsState(
      providerId: providerId,
      imdbId: null,
      pendingAction: null,
      initialLoading: true,
      loadStatus: DetailsLoadStatus.loading,
      hasError: false,
      message: '',
      tracked: false,
      posterPath: null,
      backdropPath: null,
      title: null,
      year: null,
      overview: null,
      firstAired: null,
      popularity: null,
      voteCount: null,
      externalRatings: null,
      network: null,
      country: null,
      certification: null,
      status: ShowStatus.unknown,
      language: null,
      genres: [],
      runtime: null,
      airedEpisodes: 0,
      nextEpisodeAirDate: null,
      trailer: null,
      homepage: null,
      watchedEpisodes: 0,
      lastWatchedAt: null,
      userRating: null,
      watchListed: false,
      dropped: false,
      favorite: false,
      seasons: [],
      actorsRegulars: [],
      actorsGuests: [],
      externalLinks: [],
      watchedHistory: [],
      related: [],
      watchProviderRegionSet: false,
      watchProviders: [],
    );
  }
}

extension ShowDetailsStateActions on ShowDetailsState {
  /// What the mark-as-watched flow should act on. Always available — a show's TMDB id is the
  /// page's own [ShowDetailsState.providerId], so nothing has to load first.
  MarkAsWatchedTarget get markAsWatchedTarget {
    return MarkAsWatchedTarget(
      type: ItemType.show,
      showTmdbId: providerId,
      title: title ?? '-No title available-',
      subtitle: 'Every aired episode',
    );
  }

  ShowRef get ref => ShowRef(tmdbId: providerId, imdbId: imdbId, title: title, year: year);

  /// How much of this show has been watched, against the aired count so a still-running show can
  /// read as complete.
  DetailsWatchedStatus get watchedStatus {
    return DetailsWatchedStatus(watched: watchedEpisodes, total: airedEpisodes, lastWatchedAt: lastWatchedAt);
  }
}

/// A single entry in the user's watch history for an episode of this show.
///
/// Entries span every season, so each one carries both numbers and can label
/// itself `S2E7`.
@freezed
abstract class ShowWatchEntry with _$ShowWatchEntry {
  const factory ShowWatchEntry({
    required int historyId,
    required int season,
    required int episode,
    required DateTime watchedAt,
    required HistoryAction action,
  }) = _ShowWatchEntry;
}
