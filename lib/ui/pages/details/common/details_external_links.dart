import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/link_opener.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';

/// Row of circular external-source icons (TMDB / IMDb / Trailer / Website / socials),
/// hidden entirely when there are no links. Tapping one opens it in the external browser.
///
/// The default margin matches the stats-row gutter so the row can sit directly under it;
/// pass [margin] EdgeInsets.zero when a surrounding DetailsSection already supplies the gutter.
class DetailsExternalLinks extends StatelessWidget {
  final List<DetailsExternalLink> links;
  final WrapAlignment alignment;
  final EdgeInsetsGeometry? margin;

  const DetailsExternalLinks({required this.links, this.alignment = WrapAlignment.center, this.margin, super.key});

  @override
  Widget build(BuildContext context) {
    if (links.isEmpty) {
      return const SizedBox();
    }

    return Container(
      width: double.infinity,
      margin: margin ?? ScreenSizeUtil.fromLTRB(14, 14, 14, 0),
      child: Wrap(
        alignment: alignment,
        spacing: ScreenSizeUtil.calculateSize(28),
        runSpacing: ScreenSizeUtil.calculateSize(10),
        children: links.map((link) => _LinkWidget(link, onTap: () => unawaited(openExternalLink(context, link.url)))).toList(),
      ),
    );
  }
}

class _LinkWidget extends StatelessWidget {
  final DetailsExternalLink link;
  final VoidCallback onTap;

  const _LinkWidget(this.link, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = ScreenSizeUtil.calculateSize(44);

    return InkWell(
      borderRadius: BorderRadius.circular(size / 2),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35), shape: BoxShape.circle),
            child: Icon(link.icon, size: ScreenSizeUtil.calculateSize(22), color: link.iconColor ?? colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: ScreenSizeUtil.calculateSize(6)),
          Text(link.label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
