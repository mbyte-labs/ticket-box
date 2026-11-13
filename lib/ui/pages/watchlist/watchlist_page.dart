import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/watchlist/mobile/watchlist_mobile_page.dart';
import 'package:ticketbox/ui/pages/watchlist/watchlist_bloc.dart';

class WatchlistPage extends StatelessWidget {
  const WatchlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => WatchlistBloc(),
      child: const AdaptiveLayoutBuilder.single(child: WatchlistMobilePage()),
    );
  }
}
