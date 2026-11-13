import 'package:flutter/material.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/pills/rating_pill.dart';

class PosterBottomRightPills extends StatelessWidget {
  final PosterModel details;

  const PosterBottomRightPills(this.details, {super.key});

  @override
  Widget build(BuildContext context) {
    List<Widget> pills = [];

    final rating = details.rating;
    if (rating != null) {
      pills.add(PosterRatingPill(rating));
    }

    if (pills.isEmpty) {
      return const SizedBox();
    }

    return Container(
      alignment: Alignment.bottomRight,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.end, children: pills),
    );
  }
}
