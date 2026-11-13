import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:simple_icons/simple_icons.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';
import 'package:ticketbox/database/sql_store/job_state/job_error_code.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/person/person_credit.dart';
import 'package:ticketbox/service/person/person_service.dart';
import 'package:ticketbox/service/progress/progress_error_classifier.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_state.dart';
import 'package:ticketbox/ui/pages/details/person/person_filmography_filter.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

class PersonDetailsBloc extends Cubit<PersonDetailsState> {
  static final _log = Logger('PersonDetailsBloc');

  static const notFoundMessage = 'This person could not be found.';
  static const unreachableMessage =
      "TMDB is unreachable right now, and a person's page is always fetched live — try again in a moment. Your library is unaffected.";

  /// The user-data tables the library marks are read from; a change to any of them re-marks the
  /// cards. The catalogue is deliberately not among them — this page never writes to it.
  static const _markSources = {
    DataChangeEvent.historyRepo,
    DataChangeEvent.watchlistRepo,
    DataChangeEvent.userRatingRepo,
    DataChangeEvent.showStateRepo,
  };

  StreamSubscription<Set<DataChangeEvent>>? _dataChanges;

  /// [args] is what the opening cast card already knew (name, headshot): it fills the hero header
  /// from the first frame instead of after the request. See [PersonRouteArgs].
  PersonDetailsBloc(int personTmdbId, {PersonRouteArgs? args})
    : super(PersonDetailsState.initial(personTmdbId, name: args?.name, photoUrl: args?.photoUrl));

  @override
  Future<void> close() async {
    await _dataChanges?.cancel();
    await super.close();
  }

  /// One TMDB request, a few local reads, one emit. The page is read-only: there is no local person
  /// table to serve from first (a person is visited rarely enough that it would not be worth a
  /// `schemaVersion` bump), and nothing about the person or their titles is written back — the
  /// filmography renders the credits payload as it is.
  ///
  /// Both stages log their time since the page opened (one cumulative stopwatch), so a slow page
  /// can be read off the log file: the request, or the database.
  Future<void> init() async {
    final stopwatch = Stopwatch()..start();
    final personTmdbId = state.providerId;

    final PersonDetails person;
    try {
      final quality = await KeyValueStore.instance().getEnumOrDefault(
        GeneralPropertiesKeys.posterQuality,
        PosterQualityOption.values,
        PosterQualityOption.medium,
      );
      person = await PersonService().get(personTmdbId, quality);
      _log.fine('Person $personTmdbId payload ready (${person.filmography.length} titles) in ${stopwatch.elapsedMilliseconds}ms');
    } on PersonNotFoundException catch (e) {
      // A dead link rather than a failure: TMDB has no person under this id (merged or removed).
      _log.warning('Person $personTmdbId not found on TMDB: $e');
      if (isClosed) return;
      emit(state.copyWith(initialLoading: false, hasError: true, message: notFoundMessage));
      return;
    } catch (e, stackTrace) {
      _log.severe('Error loading person details for $personTmdbId', e, stackTrace);
      if (isClosed) return;
      emit(state.copyWith(initialLoading: false, hasError: true, message: errorMessageFor(e)));
      return;
    }
    if (isClosed) return;

    final filmography = await _marked(person.filmography);
    _log.fine('Person $personTmdbId library marks ready in ${stopwatch.elapsedMilliseconds}ms');
    if (isClosed) return;

    emit(
      state.copyWith(
        initialLoading: false,
        hasError: false,
        message: '',
        name: person.name,
        photoUrl: person.photoUrl,
        biography: person.biography,
        knownForDepartment: person.knownForDepartment,
        birthday: person.birthday,
        death: person.death,
        birthplace: person.birthplace,
        alsoKnownAs: person.alsoKnownAs,
        externalLinks: _buildExternalLinks(person),
        filmography: filmography,
      ),
    );

    // The marks come from the user's own tables, so a play, rating or watchlist change made on a
    // title's page while this one is on the stack shows on the cards once the user comes back.
    _dataChanges = DataChangeMonitor.instance().changes.listen((events) {
      if (events.any(_markSources.contains)) {
        unawaited(_remark());
      }
    });
  }

  void selectFilter(PersonFilmographyFilter filter) {
    if (filter != state.filter) {
      emit(state.copyWith(filter: filter));
    }
  }

  /// The page's copy for a failed request: TMDB not answering (offline, down, rate limited) is
  /// one message, because there is no stale copy to show instead; anything else names the fault.
  @visibleForTesting
  static String errorMessageFor(Object error) {
    return switch (classifyJobError(error)) {
      JobErrorCode.networkError || JobErrorCode.serviceDown || JobErrorCode.rateLimited => unreachableMessage,
      _ => 'Loading failed (${error.runtimeType}).',
    };
  }

  Future<void> _remark() async {
    final filmography = await _marked(state.filmography);
    if (isClosed) return;
    emit(state.copyWith(filmography: filmography));
  }

  /// Never throws: a database problem costs the marks, not the page.
  Future<List<PersonCredit>> _marked(List<PersonCredit> filmography) async {
    try {
      return await PersonService().withLibraryMarks(filmography);
    } catch (e, stackTrace) {
      _log.warning('Could not mark the filmography of person ${state.providerId} against the library: $e', e, stackTrace);
      return filmography;
    }
  }

  /// The links the page opens: the person's TMDB page always leads, IMDb when TMDB knows the id;
  /// the socials (already full URLs, built by `PersonService`) follow in a fixed order, skipping
  /// the ones TMDB did not return, same "degrade gracefully" spirit as the rest of the page.
  List<DetailsExternalLink> _buildExternalLinks(PersonDetails person) {
    final links = <DetailsExternalLink>[
      DetailsExternalLink(
        label: 'TMDB',
        url: 'https://www.themoviedb.org/person/${state.providerId}',
        icon: SimpleIcons.themoviedatabase,
        iconColor: ThemeColors.brandTmdb,
      ),
    ];

    final imdbId = person.imdbId;
    if (imdbId != null && imdbId.isNotEmpty) {
      links.add(
        DetailsExternalLink(
          label: 'IMDb',
          url: 'https://www.imdb.com/name/$imdbId/',
          icon: SimpleIcons.imdb,
          iconColor: ThemeColors.brandImdb,
        ),
      );
    }

    final twitter = person.twitter;
    if (twitter != null && twitter.isNotEmpty) {
      links.add(DetailsExternalLink(label: 'X', url: twitter, icon: SimpleIcons.x));
    }

    final instagram = person.instagram;
    if (instagram != null && instagram.isNotEmpty) {
      links.add(DetailsExternalLink(label: 'Instagram', url: instagram, icon: SimpleIcons.instagram));
    }

    final facebook = person.facebook;
    if (facebook != null && facebook.isNotEmpty) {
      links.add(DetailsExternalLink(label: 'Facebook', url: facebook, icon: SimpleIcons.facebook));
    }

    final wikipedia = person.wikipedia;
    if (wikipedia != null && wikipedia.isNotEmpty) {
      links.add(DetailsExternalLink(label: 'Wikipedia', url: wikipedia, icon: SimpleIcons.wikipedia));
    }

    final homepage = person.homepage;
    if (homepage != null && homepage.isNotEmpty) {
      links.add(DetailsExternalLink(label: 'Website', url: homepage, icon: Icons.public));
    }

    return links;
  }
}
