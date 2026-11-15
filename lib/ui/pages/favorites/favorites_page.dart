import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/ui/adaptive_layout_builder.dart';
import 'package:ticketbox/ui/pages/favorites/favorites_bloc.dart';
import 'package:ticketbox/ui/pages/favorites/mobile/favorites_mobile_page.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      lazy: false,
      create: (BuildContext context) => FavoritesBloc(),
      child: const AdaptiveLayoutBuilder.single(child: FavoritesMobilePage()),
    );
  }
}
