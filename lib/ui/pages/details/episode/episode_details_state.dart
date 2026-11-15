import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/title_builder.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_status.dart';

part 'episode_details_state.freezed.dart';

@freezed
abstract class EpisodeDetailsState with _$EpisodeDetailsState {
  const factory EpisodeDetailsState({
    /// (show TMDB id, season number, episode number)
    required Tuple3<int, int, int> providerId,

    /// The episode's IMDb id, for the external link. Null until looked up or when TMDB has none.
    required String? imdbId,
    required bool initialLoading,
    required DetailsLoadStatus loadStatus,
    required bool hasError,
    required String message,

    /// Whether the parent show is in the library.
    required bool tracked,

    /// The episode's still and the show's backdrop, as TMDB relative paths.
    required String? stillPath,
    required String? backdropPath,
    required String? title,

    /// Title of the show this episode belongs to (used by the context breadcrumb)
    required String? showTitle,
    required String? overview,
    required DateTime? firstAired,

    /// TMDB and IMDb community ratings for the second row of the Ratings card.
    /// Null until the first (cached or fresh) answer arrives.
    required ExternalRatings? externalRatings,

    /// Meta of the parent show, shown in the episode's meta strip
    required String? network,
    required String? language,
    required List<String> genres,

    /// Episode's runtime in minutes
    required int? runtime,
    required String? userRating,
    required bool watchListed,
    required bool dropped,

    /// The action bar write currently in flight, if any.
    required DetailsPendingAction? pendingAction,
    required List<CastMember> actorsRegulars,
    required List<CastMember> actorsGuests,
    required List<DetailsExternalLink> externalLinks,

    /// Watch history entries for this episode, newest first
    required List<EpisodeWatchEntry> watchedHistory,

    /// Whether the user has picked a streaming country in the settings. While false the
    /// Watch now section renders nothing — the "set your country" nudge lives on the up-next
    /// dashboard instead.
    required bool watchProviderRegionSet,

    /// Subscription services streaming the parent show in the user's country, most relevant
    /// first — the snapshot carries providers at show level only.
    required List<DetailsWatchProvider> watchProviders,

    /// JustWatch offer page opened by tapping any provider logo (the parent show's page). Null
    /// when TMDB has no offer link, which leaves the logos inert.
    String? watchProviderLink,
  }) = _EpisodeDetailsState;

  factory EpisodeDetailsState.initial(Tuple3<int, int, int> providerId) {
    return EpisodeDetailsState(
      providerId: providerId,
      imdbId: null,
      pendingAction: null,
      initialLoading: true,
      loadStatus: DetailsLoadStatus.loading,
      hasError: false,
      message: '',
      tracked: false,
      stillPath: null,
      backdropPath: null,
      title: null,
      showTitle: null,
      overview: null,
      firstAired: null,
      externalRatings: null,
      network: null,
      language: null,
      genres: [],
      runtime: null,
      userRating: null,
      watchListed: false,
      dropped: false,
      actorsRegulars: [],
      actorsGuests: [],
      externalLinks: [],
      watchedHistory: [],
      watchProviderRegionSet: false,
      watchProviders: [],
    );
  }
}

extension EpisodeDetailsStateActions on EpisodeDetailsState {
  /// What the mark-as-watched flow should act on. Always available — the show id and numbering
  /// in [providerId] are the whole identity.
  MarkAsWatchedTarget get markAsWatchedTarget {
    return MarkAsWatchedTarget(
      type: ItemType.episode,
      showTmdbId: providerId.item1,
      season: providerId.item2,
      episode: providerId.item3,
      title: showTitle ?? '-No title available-',
      subtitle: ConfirmationTitleBuilder.episodeTitleFromParts(providerId.item2, providerId.item3, title),
    );
  }

  /// How much of this page's subject has been watched. An episode is binary, so the most recent
  /// play is what dates the button.
  DetailsWatchedStatus get watchedStatus {
    return DetailsWatchedStatus.single(
      watched: watchedHistory.isNotEmpty,
      lastWatchedAt: watchedHistory.isEmpty ? null : watchedHistory.first.watchedAt,
    );
  }
}

/// A single entry in the user's watch history for this episode.
@freezed
abstract class EpisodeWatchEntry with _$EpisodeWatchEntry {
  const factory EpisodeWatchEntry({required int historyId, required DateTime watchedAt, required HistoryAction action}) =
      _EpisodeWatchEntry;
}
