import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/details/episode/episode_details_bloc.dart';
import 'package:ticketbox/ui/pages/details/episode/mobile/episode_details_mobile_page.dart';

class EpisodeDetailsPage extends StatelessWidget {
  final Tuple3<int, int, int> _providerId;

  const EpisodeDetailsPage(this._providerId, {super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => EpisodeDetailsBloc(_providerId),
      child: const AdaptiveLayoutBuilder.single(child: EpisodeDetailsMobilePage()),
    );
  }
}
