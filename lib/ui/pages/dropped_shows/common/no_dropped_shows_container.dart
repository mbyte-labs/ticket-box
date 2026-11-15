import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';

/// The empty state of the dropped shows grid.
class NoDroppedShowsContainer extends StatelessWidget {
  const NoDroppedShowsContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate([
        const TicketBoxLogoWidget(topMargin: 15, imageSize: 3),
        Padding(
          padding: ScreenSizeUtil.fromLTRB(0, 30, 0, 0),
          child: const Text("You haven't dropped any shows", textAlign: TextAlign.center, style: TextStyle(fontSize: 15)),
        ),
        Padding(
          padding: ScreenSizeUtil.fromLTRB(10, 15, 10, 0),
          child: const Text(
            'Dropping a show from its page hides it from Up Next and Show Progress. Dropped shows are listed here.',
            textAlign: TextAlign.center,
          ),
        ),
      ]),
    );
  }
}
