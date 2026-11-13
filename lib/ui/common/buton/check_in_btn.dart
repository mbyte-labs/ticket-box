import 'package:flutter/material.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';

class CheckInButton extends StatelessWidget {
  final VoidCallback? onPressed;

  const CheckInButton({this.onPressed, super.key});

  @override
  Widget build(BuildContext context) {
    final actions = context.actionColors;
    final style = ElevatedButton.styleFrom(backgroundColor: actions.checkIn, foregroundColor: actions.onAction);
    return ElevatedButton(style: style, onPressed: onPressed, child: const Text('Check In'));
  }
}
