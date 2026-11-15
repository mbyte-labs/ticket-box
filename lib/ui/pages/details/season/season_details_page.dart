import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/details/season/mobile/season_details_mobile_page.dart';
import 'package:ticketbox/ui/pages/details/season/season_details_bloc.dart';

class SeasonDetailsPage extends StatelessWidget {
  final Tuple2<int, int> _providerId;

  const SeasonDetailsPage(this._providerId, {super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => SeasonDetailsBloc(_providerId),
      child: const AdaptiveLayoutBuilder.single(child: SeasonDetailsMobilePage()),
    );
  }
}
