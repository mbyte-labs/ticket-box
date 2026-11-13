import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/data_change_monitor.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_service.dart';

/// The three headline numbers under the drawer header, computed from the local library and kept
/// current while the drawer is open.
class LocalStatsBloc extends Cubit<HeadlineStats?> {
  static final _log = Logger('[Bloc] LocalStatsBloc');

  StreamSubscription<Set<DataChangeEvent>>? _changes;

  LocalStatsBloc() : super(null) {
    _changes = DataChangeMonitor.instance().changes.listen((events) {
      if (events.contains(DataChangeEvent.historyRepo) || events.contains(DataChangeEvent.showStateRepo)) {
        unawaited(load());
      }
    });
  }

  Future<void> load() async {
    try {
      final overview = await StatsService().compute();
      if (!isClosed) {
        emit(overview.headline);
      }
    } catch (e, stackTrace) {
      _log.warning('Could not compute the drawer stats', e, stackTrace);
    }
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
