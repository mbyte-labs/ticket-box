import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/set_country_banner/set_country_banner_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/mobile/up_next_to_watch_mobile_page.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/up_next_to_watch_bloc.dart';

class UpNextToWatchPage extends StatelessWidget {
  const UpNextToWatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(lazy: false, create: (BuildContext context) => UpNextToWatchBloc()),
        BlocProvider(lazy: false, create: (BuildContext context) => SetCountryBannerBloc()),
      ],
      child: const AdaptiveLayoutBuilder.single(child: UpNextToWatchMobilePage()),
    );
  }
}
