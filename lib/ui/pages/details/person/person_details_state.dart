import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/service/person/person_credit.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/person/person_filmography_filter.dart';

part 'person_details_state.freezed.dart';

@freezed
abstract class PersonDetailsState with _$PersonDetailsState {
  const PersonDetailsState._();

  const factory PersonDetailsState({
    // providerId is the person's TMDB id
    required int providerId,
    required bool initialLoading,
    required bool hasError,
    required String message,
    required String? name,
    required String? photoUrl,
    required String? biography,
    required String? knownForDepartment,
    required String? birthday,
    required String? death,
    required String? birthplace,
    required List<String> alsoKnownAs,
    required List<DetailsExternalLink> externalLinks,

    /// Every acting credit, one card per title, in display order and marked against the library.
    required List<PersonCredit> filmography,
    @Default(PersonFilmographyFilter.all) PersonFilmographyFilter filter,
  }) = _PersonDetailsState;

  /// [name] and [photoUrl] are the opening card's paint-ahead hint (see `PersonRouteArgs`), so the
  /// hero header has something to show while [initialLoading] holds.
  factory PersonDetailsState.initial(int providerId, {String? name, String? photoUrl}) {
    return PersonDetailsState(
      providerId: providerId,
      initialLoading: true,
      hasError: false,
      message: '',
      name: name,
      photoUrl: photoUrl,
      biography: null,
      knownForDepartment: null,
      birthday: null,
      death: null,
      birthplace: null,
      alsoKnownAs: const [],
      externalLinks: const [],
      filmography: const [],
    );
  }

  /// The titles the user has already seen the person in — "where do I know them from?".
  List<PersonCredit> get seenWith => filmography.where((credit) => credit.inHistory).toList();

  int get movieCount => filmography.where((credit) => credit.isMovie).length;

  int get showCount => filmography.where((credit) => credit.isShow).length;

  /// The filter is only worth showing when there is something to filter between.
  bool get hasBothKinds => movieCount > 0 && showCount > 0;

  List<PersonCredit> get visibleFilmography =>
      filter == PersonFilmographyFilter.all ? filmography : filmography.where(filter.accepts).toList();
}
