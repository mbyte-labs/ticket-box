import 'package:freezed_annotation/freezed_annotation.dart';

part 'paged_response.freezed.dart';

/// Class used to store details about page number and page size. Usefull when requesting
/// an API that is paged or pass data trough isolates
@freezed
abstract class PagedResponse<T> with _$PagedResponse<T> {
  const factory PagedResponse({required int page, required int pageSize, required int totalPages, required T data}) = _PagedResponse;

  factory PagedResponse.emptyPage(T data) {
    return PagedResponse(data: data, page: 1, pageSize: 50, totalPages: 1);
  }
}
