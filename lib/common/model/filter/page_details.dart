import 'package:freezed_annotation/freezed_annotation.dart';

part 'page_details.freezed.dart';

/// Class used to store details about page number and page size. Usefully when requesting
/// an API that is paged or pass data trough isolates
@freezed
abstract class PageDetails with _$PageDetails {
  const factory PageDetails({
    /// This refers to the current page
    required int page,

    /// The number of items that a page should display
    @Default(50) int pageSize,

    /// The total number of pages that are available based on the pageSize provided
    @Default(-1) int totalPages,
  }) = _PageDetails;
}
