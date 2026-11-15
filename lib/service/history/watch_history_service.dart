import 'package:ticketbox/common/model/filter/page_details.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/paged_response.dart';
import 'package:ticketbox/database/sql_store/history/history_entity.dart';
import 'package:ticketbox/database/sql_store/history/history_repository.dart';

/// The read side of the watch history - the counterpart of [WatchHistoryWriteService], which only
/// writes.
class WatchHistoryService {
  final _repo = HistoryRepo();

  /// The plays, one entry per watch (a rewatched episode is listed once per watch), most recently
  /// watched first.
  ///
  /// [paged] pages are 1 based while the repository's are 0 based, matching
  /// [WatchlistService.get]. Unlike that method the page number is converted back on the way
  /// out, so a caller never sees the repository's numbering leak into the response.
  ///
  /// The cut off is "now": a check-in whose `watchedAt` is still in the future is an in-progress
  /// check-in owned by the check-in banner, not history.
  Future<PagedResponse<List<HistoryEntity>>> getPlays(List<ItemType> types, List<HistoryAction> actions, PageDetails paged) async {
    final repoPage = paged.copyWith(page: paged.page - 1);
    final response = await _repo.getPlays(DateTime.now().millisecondsSinceEpoch, actions, types, repoPage);

    return response.copyWith(page: paged.page);
  }
}
