import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/database/sql_store/episode/episode_entity.dart';
import 'package:ticketbox/database/sql_store/episode/episode_repository.dart';
import 'package:ticketbox/database/sql_store/movie/movie_entity.dart';
import 'package:ticketbox/database/sql_store/movie/movie_repository.dart';
import 'package:ticketbox/database/sql_store/season/season_entity.dart';
import 'package:ticketbox/database/sql_store/season/season_repository.dart';
import 'package:ticketbox/database/sql_store/show/show_entity.dart';
import 'package:ticketbox/database/sql_store/show/show_repository.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/poster/poster_model_builder.dart';
import 'package:ticketbox/service/title_builder.dart';

/// Builds the (unmarked) [PosterModel]s of a list of library keys from the local catalogue, one
/// `getMany` per table instead of a query per tile.
///
/// A key whose catalogue rows are missing (a stub the backfill has not reached yet, or a row the
/// deletion sweep already took) still gets a tile: the builder's placeholder title and no artwork,
/// so the user's list never loses an entry over a missing snapshot.
class PosterModelResolver {
  final MovieRepo _movieRepo;
  final ShowRepo _showRepo;
  final SeasonRepo _seasonRepo;
  final EpisodeRepo _episodeRepo;

  PosterModelResolver({MovieRepo? movieRepo, ShowRepo? showRepo, SeasonRepo? seasonRepo, EpisodeRepo? episodeRepo})
    : _movieRepo = movieRepo ?? MovieRepo(),
      _showRepo = showRepo ?? ShowRepo(),
      _seasonRepo = seasonRepo ?? SeasonRepo(),
      _episodeRepo = episodeRepo ?? EpisodeRepo();

  /// One model per distinct key in [keys], in that order.
  Future<List<PosterModel>> resolve(Iterable<MediaKey> keys) async {
    final distinct = keys.toSet();
    if (distinct.isEmpty) {
      return const [];
    }

    final movieIds = {
      for (final key in distinct)
        if (key.type == ItemType.movie) key.tmdbId,
    }.toList();
    final showIds = {
      for (final key in distinct)
        if (key.type != ItemType.movie) key.tmdbId,
    }.toList();
    final seasonKeys = {
      for (final key in distinct)
        if (key.type == ItemType.season || key.type == ItemType.episode) (key.tmdbId, key.season),
    };
    final episodeKeys = {
      for (final key in distinct)
        if (key.type == ItemType.episode) (key.tmdbId, key.season, key.episode),
    };

    final (movies, shows, seasons, episodes) = await (
      _movieRepo.getMany(movieIds),
      _showRepo.getMany(showIds),
      _seasonRepo.getMany(seasonKeys),
      _episodeRepo.getMany(episodeKeys),
    ).wait;

    return [
      for (final key in distinct)
        switch (key.type) {
          ItemType.movie => _movie(key, movies[key.tmdbId]),
          ItemType.show => _show(key, shows[key.tmdbId]),
          ItemType.season => _season(key, seasons[(key.tmdbId, key.season)], shows[key.tmdbId]),
          ItemType.episode => _episode(
            key,
            episodes[(key.tmdbId, key.season, key.episode)],
            seasons[(key.tmdbId, key.season)],
            shows[key.tmdbId],
          ),
        },
    ];
  }

  static PosterModel _movie(MediaKey key, MovieEntity? row) {
    if (row != null) {
      return PosterModelBuilder.movie(row);
    }
    return _placeholder(key, title: PosterModelBuilder.noTitle, noPosterText: PosterModelBuilder.noTitle);
  }

  static PosterModel _show(MediaKey key, ShowEntity? row) {
    if (row != null) {
      return PosterModelBuilder.show(row);
    }
    return _placeholder(key, title: PosterModelBuilder.noTitle, noPosterText: PosterModelBuilder.noTitle);
  }

  static PosterModel _season(MediaKey key, SeasonEntity? row, ShowEntity? show) {
    if (row != null) {
      return PosterModelBuilder.season(row, showTitle: show?.title, showPosterPath: show?.posterPath);
    }
    return _placeholder(
      key,
      title: ConfirmationTitleBuilder.seasonTitle(key.season),
      noPosterText: show?.title ?? PosterModelBuilder.noTitle,
      posterPath: show?.posterPath,
    );
  }

  static PosterModel _episode(MediaKey key, EpisodeEntity? row, SeasonEntity? season, ShowEntity? show) {
    final posterPath = season?.posterPath ?? show?.posterPath;
    if (row != null) {
      return PosterModelBuilder.episode(row, showTitle: show?.title, seasonPosterPath: posterPath);
    }
    return _placeholder(
      key,
      title: ConfirmationTitleBuilder.episodeTitleFromParts(key.season, key.episode, null),
      noPosterText: show?.title ?? PosterModelBuilder.noTitle,
      posterPath: posterPath,
    );
  }

  /// The tile of a key without a catalogue row. Not [PosterModel.tracked]: the marks pass sets
  /// that from the movies / shows tables, which is the one place that knows.
  static PosterModel _placeholder(MediaKey key, {required String title, required String noPosterText, String? posterPath}) {
    return PosterModel(key: key, title: title, noPosterText: noPosterText, posterPath: posterPath, tracked: false, rating: null);
  }
}
