import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:ticketbox/service/user/user_details_state.dart';

class UserDetailsBloc extends Cubit<UserDetailsState> {
  static final _log = Logger('UserDetailsBloc');

  UserDetailsBloc._() : super(UserDetailsState.initial());

  static UserDetailsBloc instance() {
    if (GetIt.I.isRegistered<UserDetailsBloc>()) {
      return GetIt.I.get<UserDetailsBloc>();
    }

    _log.info('New instance created');
    final bloc = UserDetailsBloc._();
    GetIt.I.registerSingleton<UserDetailsBloc>(bloc);
    return bloc;
  }

  /// There is no longer a remote account to load: the state starts from, and stays at, the
  /// application defaults until the preference pages change it.
  Future<void> loadFromDisk() async {
    _log.fine('Initializing UserDetails Bloc');
    emit(UserDetailsState.initial());
  }
}
