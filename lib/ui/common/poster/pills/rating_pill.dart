import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/heart_rating_img.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

class PosterRatingPill extends StatelessWidget {
  final String _rating;

  const PosterRatingPill(this._rating, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(width: 1, color: Colors.transparent),
        color: Colors.grey.withOpacity(0.6),
      ),
      padding: ScreenSizeUtil.fromLTRB(0, 4, 0, 4),
      child: SizedBox(
        width: ScreenSizeUtil.calculateSize(55),
        height: ScreenSizeUtil.calculateSize(15),
        child: Center(
          child: Wrap(
            spacing: 5,
            children: [
              HeartWidgetUtil.fullImage(ThemeColors.primary, 15, 15),
              Text(_rating, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class PosterUserRatingPill extends StatelessWidget {
  final String _rating;

  const PosterUserRatingPill(this._rating, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ThemeColors.primary.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(40)),
        border: Border.all(width: 3, color: Colors.transparent, style: BorderStyle.solid),
      ),
      padding: ScreenSizeUtil.fromLTRB(7, 2, 2, 2),
      child: Text(_rating),
    );
  }
}
