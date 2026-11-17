import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/details/show/mobile/show_details_mobile_page.dart';
import 'package:ticketbox/ui/pages/details/show/show_details_bloc.dart';

class ShowDetailsPage extends StatelessWidget {
  final int _providerId;

  const ShowDetailsPage(this._providerId, {super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => ShowDetailsBloc(_providerId),
      child: const AdaptiveLayoutBuilder.single(child: ShowDetailsMobilePage()),
    );
  }
}
