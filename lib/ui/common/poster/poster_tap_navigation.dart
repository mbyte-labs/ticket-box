import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';
import 'package:ticketbox/ui/routes.dart';

/// The one place that knows the details routes' path parameters. Every poster tap and every
/// "open this item" link goes through here.
class PosterNavigation {
  static final _log = Logger('[UI] PosterNavigation');

  /// Opens the details page of whatever the tile represents.
  static void navigate(BuildContext context, PosterModel poster) => navigateToKey(context, poster.key);

  static void navigateToKey(BuildContext context, MediaKey key) {
    switch (key.type) {
      case ItemType.movie:
        movieNavigateRaw(context, key.tmdbId);
      case ItemType.show:
        showNavigateRaw(context, key.tmdbId);
      case ItemType.season:
        seasonNavigateRaw(context, key.tmdbId, key.season);
      case ItemType.episode:
        episodeNavigateRaw(context, key.tmdbId, key.season, key.episode);
    }
  }

  /// The path parameters [Routes] expects for [key], exposed for tests and for callers that build
  /// a link rather than push it.
  static Map<String, String> pathParameters(MediaKey key) {
    return switch (key.type) {
      ItemType.movie => {'tmdbId': key.tmdbId.toString()},
      ItemType.show => {'showTmdbId': key.tmdbId.toString()},
      ItemType.season => {'showTmdbId': key.tmdbId.toString(), 'season': key.season.toString()},
      ItemType.episode => {'showTmdbId': key.tmdbId.toString(), 'season': key.season.toString(), 'episode': key.episode.toString()},
    };
  }

  static void movieNavigateRaw(BuildContext context, int tmdbId) {
    _log.info('Navigating to movie: $tmdbId');
    context.pushNamed(Routes.movieDetails, pathParameters: pathParameters(MediaKey.movie(tmdbId)));
  }

  static void showNavigateRaw(BuildContext context, int showTmdbId) {
    _log.info('Navigating to show: $showTmdbId');
    context.pushNamed(Routes.showDetails, pathParameters: pathParameters(MediaKey.show(showTmdbId)));
  }

  static void seasonNavigateRaw(BuildContext context, int showTmdbId, int season) {
    _log.info('Navigating to show $showTmdbId season $season');
    context.pushNamed(Routes.seasonDetails, pathParameters: pathParameters(MediaKey.season(showTmdbId, season)));
  }

  static void episodeNavigateRaw(BuildContext context, int showTmdbId, int season, int episode) {
    _log.info('Navigating to show $showTmdbId season $season episode $episode');
    context.pushNamed(Routes.episodeDetails, pathParameters: pathParameters(MediaKey.episode(showTmdbId, season, episode)));
  }

  /// [args] is what the tapping card already knows (name, headshot) so the person page can paint
  /// its header at once; see [PersonRouteArgs]. Optional: a caller with nothing to pass gets the
  /// page's own loading header.
  static void personNavigateRaw(BuildContext context, int personTmdbId, {PersonRouteArgs? args}) {
    _log.info('Navigating to person: $personTmdbId');
    context.pushNamed(Routes.personDetails, pathParameters: {'personTmdbId': personTmdbId.toString()}, extra: args);
  }
}
