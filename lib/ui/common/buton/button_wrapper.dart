import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';

class ConfirmationButtonWrapper {
  static Widget wrapButton(Widget widget) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [SizedBox(width: ScreenSizeUtil.calculateSize(370), child: widget)],
    );
  }
}
