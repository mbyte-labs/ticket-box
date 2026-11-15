import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/result_state.dart';

part 'state_data.freezed.dart';

@freezed
abstract class StateData<T> with _$StateData<T> {
  const factory StateData(ResultState state, T details) = _StateData<T>;

  factory StateData.initial(T initialDetails) {
    return StateData<T>(ResultState.notLoaded, initialDetails);
  }
}
