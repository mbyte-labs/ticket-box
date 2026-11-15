import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/discover/discover_bloc.dart';
import 'package:ticketbox/ui/pages/discover/discover_route_args.dart';
import 'package:ticketbox/ui/pages/discover/mobile/discover_mobile_page.dart';

class DiscoverPage extends StatelessWidget {
  final DiscoverRouteArgs args;

  const DiscoverPage({this.args = const DiscoverRouteArgs(), super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => DiscoverBloc(initialType: args.type, routeMode: args.mode),
      child: const AdaptiveLayoutBuilder.single(child: DiscoverMobilePage()),
    );
  }
}
