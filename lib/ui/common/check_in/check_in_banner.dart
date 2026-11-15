import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/general_widget/confirmation/check_in_remove/check_in_remove_confirmation_widget.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/check_in/check_in_bloc.dart';
import 'package:ticketbox/ui/pages/up_next_to_watch/common/check_in/check_in_state.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Identifies the item the host page is showing, so [CheckInBanner] can tell
/// "tap to go to the check-in" apart from "you are already looking at it".
///
/// Only pages that can *be* the checked-in item need one: the episode page and
/// the movie page. The show and season pages pass nothing — a
/// check-in that belongs to the show on screen is still one level down, so
/// tapping should navigate to the episode.
class CheckInBannerScope {
  final ItemType type;

  /// TMDB id of the show (for [ItemType.episode]) or of the movie.
  final int tmdbId;
  final int? season;
  final int? episode;

  const CheckInBannerScope.episode({required this.tmdbId, required this.season, required this.episode}) : type = ItemType.episode;

  const CheckInBannerScope.movie({required this.tmdbId}) : type = ItemType.movie, season = null, episode = null;

  bool matches(CheckInState state) {
    if (state.type != type || state.tmdbId != tmdbId) {
      return false;
    }
    if (type == ItemType.movie) {
      return true;
    }
    return state.season == season && state.episode == episode;
  }
}

/// The app-wide "you are currently checked in" heads-up.
///
/// Shown on the dashboard and on every details page whenever a check-in is
/// running — the point is that the user is reminded of it wherever they are, not
/// only on the page of the item itself. Renders nothing when there is no check-in.
///
/// Tapping navigates to the checked-in episode/movie; when the banner is already
/// on that item's page ([scope] matching the live state) it switches to remove
/// mode instead. A long-press opens the remove sheet in either mode, so removing
/// is always reachable without a round trip.
class CheckInBanner extends StatelessWidget {
  /// What the host page is showing, when it can be the checked-in item itself.
  final CheckInBannerScope? scope;

  const CheckInBanner({this.scope, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CheckInBloc, CheckInState>(
      buildWhen: (previous, current) =>
          previous.isWatching != current.isWatching ||
          previous.title != current.title ||
          previous.subtitle != current.subtitle ||
          previous.percentageWatched != current.percentageWatched,
      builder: (context, state) {
        if (!state.isWatching) {
          return const SizedBox.shrink();
        }

        final isCurrentItem = scope?.matches(state) ?? false;

        return Padding(
          padding: ScreenSizeUtil.fromLTRB(12, 12, 12, 0),
          child: _CheckInPill(
            state: state,
            isCurrentItem: isCurrentItem,
            onTap: () => isCurrentItem ? _remove(context, state) : _navigate(context, state),
            onLongPress: () => _remove(context, state),
          ),
        );
      },
    );
  }

  void _navigate(BuildContext context, CheckInState state) {
    final tmdbId = state.tmdbId;
    if (tmdbId == null) {
      return;
    }

    if (state.type == ItemType.movie) {
      PosterNavigation.movieNavigateRaw(context, tmdbId);
      return;
    }

    final season = state.season;
    final episode = state.episode;
    if (season == null || episode == null) {
      return;
    }
    PosterNavigation.episodeNavigateRaw(context, tmdbId, season, episode);
  }

  void _remove(BuildContext context, CheckInState state) {
    final item = state.checkInItem;
    if (item == null) {
      return;
    }
    CheckInRemoveConfirmationWidget(item).buildWidget(context);
  }
}

class _CheckInPill extends StatelessWidget {
  final CheckInState state;
  final bool isCurrentItem;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CheckInPill({required this.state, required this.isCurrentItem, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(ScreenSizeUtil.calculateSize(16));
    final progress = (state.percentageWatched / 100).clamp(0.0, 1.0);

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        onLongPress: onLongPress,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: ThemeColors.actionCheckInAccent.withValues(alpha: 0.45)),
          ),
          // Keeps the progress bar below flush with the rounded bottom edge.
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              children: [
                Padding(
                  padding: ScreenSizeUtil.fromLTRB(12, 10, 12, 10),
                  child: Row(
                    children: [
                      const _LiveIcon(),
                      SizedBox(width: ScreenSizeUtil.calculateSize(10)),
                      Expanded(
                        child: _Labels(state: state, isCurrentItem: isCurrentItem),
                      ),
                      SizedBox(width: ScreenSizeUtil.calculateSize(8)),
                      Text(
                        '${state.percentageWatched.toInt()}%',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                      ),
                      Icon(
                        isCurrentItem ? Icons.close : Icons.chevron_right,
                        size: ScreenSizeUtil.calculateSize(20),
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
                _ProgressBar(progress: progress),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveIcon extends StatelessWidget {
  const _LiveIcon();

  @override
  Widget build(BuildContext context) {
    final size = ScreenSizeUtil.calculateSize(32);

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: ThemeColors.transparentRed, shape: BoxShape.circle),
      child: Icon(Icons.play_arrow_rounded, size: ScreenSizeUtil.calculateSize(20), color: ThemeColors.actionCheckInAccent),
    );
  }
}

class _Labels extends StatelessWidget {
  final CheckInState state;
  final bool isCurrentItem;

  const _Labels({required this.state, required this.isCurrentItem});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitle = state.subtitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isCurrentItem ? 'CHECKED IN HERE' : 'CHECKED IN',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: ThemeColors.actionCheckInAccent),
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(2)),
        Text(
          subtitle.isEmpty ? state.title : '${state.title} · $subtitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double progress;

  const _ProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    // Same recipe as the details action bar's watch progress, minus the rounding —
    // the enclosing ClipRRect already rounds it into the card's bottom corners.
    return LinearProgressIndicator(
      value: progress,
      minHeight: ScreenSizeUtil.calculateSize(3),
      backgroundColor: Colors.transparent,
      valueColor: const AlwaysStoppedAnimation<Color>(ThemeColors.actionCheckInAccent),
    );
  }
}
