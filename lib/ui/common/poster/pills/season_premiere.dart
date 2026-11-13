import 'package:flutter/material.dart';

class SeasonPremierePill extends StatelessWidget {
  static final _decoration = BoxDecoration(
    border: Border.all(width: 0, color: Colors.transparent),
    color: Colors.green.withOpacity(0.7),
  );

  const SeasonPremierePill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 105,
      height: 20,
      decoration: _decoration,
      child: const Center(child: Text('Season Premiere', style: TextStyle(fontSize: 12))),
    );
  }
}
