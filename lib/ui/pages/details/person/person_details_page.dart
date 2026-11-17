import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/details/person/mobile/person_details_mobile_page.dart';
import 'package:ticketbox/ui/pages/details/person/person_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';

class PersonDetailsPage extends StatelessWidget {
  final int _personTmdbId;

  /// What the opening card already knew about the person, if anything; see [PersonRouteArgs].
  final PersonRouteArgs? args;

  const PersonDetailsPage(this._personTmdbId, {this.args, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => PersonDetailsBloc(_personTmdbId, args: args),
      child: const AdaptiveLayoutBuilder.single(child: PersonDetailsMobilePage()),
    );
  }
}
