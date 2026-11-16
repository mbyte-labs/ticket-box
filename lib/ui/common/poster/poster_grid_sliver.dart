import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/user/user_details_bloc.dart';
import 'package:ticketbox/ui/common/poster/poster_with_title.dart';
import 'package:ticketbox/ui/theme/poster_size_calculator.dart';

/// The poster grid the list pages share: a sliver of [PosterWithTitle] tiles sized by the user's
/// poster size preference.
///
/// The tiles are keyed by the model's grid id (or by [tileKeyOf] when given), so a rebuild that
/// reorders [models] re-parents the existing elements instead of rebuilding them - no flicker and
/// no lost scroll offset. That is also why the keys must be unique: duplicate sibling keys are a
/// hard error. A grid that lists one title more than once - the watch history, one tile per play -
/// must therefore pass its own [tileKeyOf].
class PosterGridSliver extends StatelessWidget {
  final List<PosterModel> models;
  final void Function(BuildContext context, PosterModel model) onTap;
  final void Function(BuildContext context, PosterModel model)? onLongPress;

  /// [onLongPress] by position, for a grid whose models are not unique (one tile per play), where
  /// the model alone cannot say which tile was pressed. Wins over [onLongPress] when both are set.
  final void Function(BuildContext context, int index)? onLongPressAt;

  /// The key of the tile at an index of [models]; defaults to the model's grid id.
  final Key Function(int index)? tileKeyOf;

  /// The subtitle line of the tile at an index of [models]; none when null or absent.
  final String? Function(int index)? subtitleOf;

  const PosterGridSliver({
    required this.models,
    required this.onTap,
    this.onLongPress,
    this.onLongPressAt,
    this.tileKeyOf,
    this.subtitleOf,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final posterSize = context.select((UserDetailsBloc b) => b.state.appPreferences.posterSize);

    return SliverPadding(
      padding: ScreenSizeUtil.fromLTRB(5, 10, 5, 0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          childAspectRatio: PosterSizeCalculator.geAspectRatio(posterSize),
          maxCrossAxisExtent: PosterSizeCalculator.getSize(posterSize),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          final model = models[index];
          return PosterWithTitle(
            key: tileKeyOf?.call(index) ?? Key('${model.id}'),
            model: model,
            subtitle: subtitleOf?.call(index),
            onTap: (model) => onTap(context, model),
            onLongPress: onLongPressAt != null
                ? (_) => onLongPressAt!(context, index)
                : onLongPress == null
                ? null
                : (model) => onLongPress!(context, model),
          );
        }, childCount: models.length),
      ),
    );
  }
}
