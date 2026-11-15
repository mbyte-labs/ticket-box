import 'package:flutter/material.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/heart_rating_img.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

class ConfirmationSelectRating extends StatelessWidget {
  final void Function(double rating) onRatingUpdate;

  const ConfirmationSelectRating({required this.onRatingUpdate, super.key});

  @override
  Widget build(BuildContext context) {
    const heartColor = ThemeColors.primary;
    return RatingBar(
      initialRating: 0,
      direction: Axis.horizontal,
      allowHalfRating: false,
      itemCount: 10,
      minRating: 0,
      itemSize: ScreenSizeUtil.calculateSize(30),
      ratingWidget: RatingWidget(
        full: HeartWidgetUtil.fullImage(heartColor, 30, 30),
        half: HeartWidgetUtil.halfImage(heartColor, 30, 30),
        empty: HeartWidgetUtil.emptyImage(heartColor, 30, 30),
      ),
      itemPadding: EdgeInsets.symmetric(horizontal: ScreenSizeUtil.calculateSize(4)),
      onRatingUpdate: (rating) {
        onRatingUpdate(rating);
      },
    );
  }
}
