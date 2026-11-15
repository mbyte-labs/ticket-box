import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/watch_history/mobile/watch_history_mobile_page.dart';
import 'package:ticketbox/ui/pages/watch_history/watch_history_bloc.dart';

class WatchHistoryPage extends StatelessWidget {
  const WatchHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => WatchHistoryBloc(),
      child: const AdaptiveLayoutBuilder.single(child: WatchHistoryMobilePage()),
    );
  }
}
