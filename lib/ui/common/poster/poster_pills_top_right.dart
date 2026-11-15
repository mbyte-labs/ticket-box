import 'package:flutter/material.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/pills/rating_pill.dart';

class PosterTopRightPills extends StatelessWidget {
  final PosterModel details;

  const PosterTopRightPills(this.details, {super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> pills = [];

    final userRating = details.marks.userRating;
    if (userRating != null) {
      pills.add(PosterUserRatingPill(userRating));
    }

    if (pills.isEmpty) {
      return const SizedBox();
    }

    return Container(
      alignment: Alignment.topRight,
      child: Column(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.end, children: pills),
    );
  }
}
