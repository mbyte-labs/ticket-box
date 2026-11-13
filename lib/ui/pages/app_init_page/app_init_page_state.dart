import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_init_page_state.freezed.dart';

@freezed
abstract class AppInitPageState with _$AppInitPageState {
  const factory AppInitPageState({
    required ActionSType action,

    /// If something goes wrong
    required bool hasError,
    required String message,
    required String? namedRouteRedirect,
  }) = _AppInitPageState;

  factory AppInitPageState.initial() {
    return const AppInitPageState(action: ActionSType.init, hasError: false, message: 'Starting application', namedRouteRedirect: null);
  }
}

enum ActionSType {
  @JsonValue('init')
  init,
  @JsonValue('finishedWork')
  finishedWork,
}
