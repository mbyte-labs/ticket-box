import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/loading/progress_indicator.dart';
import 'package:ticketbox/ui/general_widget/ticket_box_widget.dart';

class SliverPageLoading extends StatelessWidget {
  final double topMargin;
  final double bottomMargin;
  final String displayText;
  final double spaceBetweenLogoAndSpinner;

  const SliverPageLoading(this.displayText, {this.spaceBetweenLogoAndSpinner = 120, this.topMargin = 15, this.bottomMargin = 0, super.key});

  @override
  Widget build(BuildContext context) {
    return SliverList(
      delegate: SliverChildListDelegate.fixed([
        TicketBoxLogoWidget(topMargin: topMargin, bottomMargin: bottomMargin),
        SizedBox(height: ScreenSizeUtil.calculateSize(spaceBetweenLogoAndSpinner)),
        const CircularProgressIndicatorSpinningLines(),
        SizedBox(height: ScreenSizeUtil.calculateSize(20)),
        Container(
          margin: ScreenSizeUtil.fromLTRB(10, 0, 10, bottomMargin),
          child: Text(displayText, style: const TextStyle(fontSize: 14), textAlign: TextAlign.center),
        ),
      ]),
    );
  }
}
