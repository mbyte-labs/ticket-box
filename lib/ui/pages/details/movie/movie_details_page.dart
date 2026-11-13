import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/details/movie/mobile/movie_details_mobile_page.dart';
import 'package:ticketbox/ui/pages/details/movie/movie_details_bloc.dart';

class MovieDetailsPage extends StatelessWidget {
  final int _providerId;

  const MovieDetailsPage(this._providerId, {super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => MovieDetailsBloc(_providerId),
      child: const AdaptiveLayoutBuilder.single(child: MovieDetailsMobilePage()),
    );
  }
}
