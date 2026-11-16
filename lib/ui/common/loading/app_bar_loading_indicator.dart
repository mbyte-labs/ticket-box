import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/database/sql_store/job_state/job_constants.dart';
import 'package:ticketbox/database/sql_store/job_state/job_state_repository.dart';

/// A thin loading bar under the app bar while a background job is running: the show progress
/// refresh (aired counts and Up Next recomputed from TMDB) or the TMDB account sync.
///
/// It should only be used on the AppBar!!!
class AppBarLoadingIndicatorWidget extends StatefulWidget {
  const AppBarLoadingIndicatorWidget({super.key});

  @override
  State<AppBarLoadingIndicatorWidget> createState() => _AppBarLoadingIndicatorWidgetState();
}

class _AppBarLoadingIndicatorWidgetState extends State<AppBarLoadingIndicatorWidget> {
  /// Built once and held, so a rebuild does not re-subscribe to the underlying Drift query.
  late final Stream<bool> _anyRunning = JobStateRepo().streamAnyRunning([PROGRESS_REFRESH_JOB_ID, TMDB_SYNC_JOB_ID]);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _anyRunning,
      builder: (context, snapshot) {
        if (snapshot.data != true) {
          return const SizedBox();
        }
        return const LinearProgressIndicator(minHeight: 2.5);
      },
    );
  }
}
