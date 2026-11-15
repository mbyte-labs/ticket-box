import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// GitHub-style calendar of plays per day over the last year: one column per week, Monday at
/// the top, darker to brighter by how busy the day was. A year of weeks does not fit a phone at
/// a readable size, so the grid scrolls horizontally and opens on the latest weeks. Tapping a
/// day names it and its play count below the grid.
class PlaysHeatmap extends StatefulWidget {
  final DailyPlays daily;

  const PlaysHeatmap(this.daily, {super.key});

  /// The fill of each shade, index 0 being a day without plays.
  static final shadeColors = [
    ThemeColors.dark4,
    for (final alpha in const [0.3, 0.55, 0.8, 1.0]) ThemeColors.primary.withValues(alpha: alpha),
  ];

  @override
  State<PlaysHeatmap> createState() => _PlaysHeatmapState();
}

class _PlaysHeatmapState extends State<PlaysHeatmap> {
  /// The tapped day's bucket index, or null before the first tap.
  int? _selected;

  @override
  void didUpdateWidget(PlaysHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A recompute may have moved the window by a day, so the old index would name another date.
    if (oldWidget.daily != widget.daily) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final daily = widget.daily;
    final layout = _HeatmapLayout(daily);
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500) ?? const TextStyle(color: ThemeColors.greyScale500);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeekdayGutter(layout: layout, style: labelStyle),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                // Starts at the end, so the latest weeks are what shows first.
                reverse: true,
                child: GestureDetector(
                  onTapUp: (details) {
                    final index = layout.indexAt(details.localPosition);
                    if (index != null) {
                      setState(() => _selected = index);
                    }
                  },
                  child: CustomPaint(
                    size: layout.size,
                    painter: _HeatmapPainter(layout: layout, selected: _selected, labelStyle: labelStyle),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(6)),
        Text(
          _selected == null
              ? 'Tap a day for its plays'
              : '${DateFormat.yMMMEd().format(daily.day(_selected!))} · ${_plays(daily.plays[_selected!])}',
          style: _selected == null ? labelStyle : textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(4)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text('${_plays(daily.total)} on ${_days(daily.activeDays)}', style: labelStyle)),
            _Legend(cellSize: layout.cell, style: labelStyle),
          ],
        ),
      ],
    );
  }

  static String _plays(int plays) => plays == 1 ? '1 play' : '$plays plays';

  static String _days(int days) => days == 1 ? '1 day' : '$days days';
}

/// The geometry of the grid, shared by the painter, the hit test and the weekday gutter.
class _HeatmapLayout {
  /// Labels closer than this many columns to the previous one would overlap it.
  static const _minLabelColumns = 3;

  final DailyPlays daily;
  final double cell = ScreenSizeUtil.calculateSize(11);
  final double gap = ScreenSizeUtil.calculateSize(2);
  final double header = ScreenSizeUtil.calculateSize(16);

  /// Empty slots above the first day, so every column runs Monday to Sunday.
  late final int leading = daily.start.weekday - DateTime.monday;
  late final int columns = (leading + daily.plays.length + DateTime.daysPerWeek - 1) ~/ DateTime.daysPerWeek;

  _HeatmapLayout(this.daily);

  double get pitch => cell + gap;

  Size get size => Size(columns * pitch - gap, header + DateTime.daysPerWeek * pitch - gap);

  /// The top-left corner of a row of cells, for the weekday labels.
  double rowTop(int row) => header + row * pitch;

  Rect cellRect(int index) {
    final slot = leading + index;
    final column = slot ~/ DateTime.daysPerWeek;
    final row = slot % DateTime.daysPerWeek;
    return Rect.fromLTWH(column * pitch, rowTop(row), cell, cell);
  }

  /// The bucket under [position], or null outside the days of the grid.
  int? indexAt(Offset position) {
    if (position.dy < header || position.dx < 0) {
      return null;
    }
    final column = position.dx ~/ pitch;
    final row = (position.dy - header) ~/ pitch;
    if (column >= columns || row >= DateTime.daysPerWeek) {
      return null;
    }
    final index = column * DateTime.daysPerWeek + row - leading;
    return index >= 0 && index < daily.plays.length ? index : null;
  }

  /// The column each month label sits over: the start's month at column 0, then the column of
  /// every 1st, dropping any label that would crowd the one before it.
  List<(int column, DateTime month)> monthLabels() {
    final labels = <(int, DateTime)>[];
    for (var index = 0; index < daily.plays.length; index++) {
      final day = daily.day(index);
      if (index != 0 && day.day != 1) {
        continue;
      }
      final column = (leading + index) ~/ DateTime.daysPerWeek;
      if (labels.isNotEmpty && column - labels.last.$1 < _minLabelColumns) {
        // A 1st right after the start beats the partial month the grid opened with.
        if (labels.length == 1 && labels.last.$1 == 0 && day.day == 1) {
          labels.removeLast();
        } else {
          continue;
        }
      }
      labels.add((column, day));
    }
    return labels;
  }
}

class _HeatmapPainter extends CustomPainter {
  final _HeatmapLayout layout;
  final int? selected;
  final TextStyle labelStyle;

  _HeatmapPainter({required this.layout, required this.selected, required this.labelStyle});

  @override
  void paint(Canvas canvas, Size size) {
    final daily = layout.daily;
    final shades = daily.shades();
    final radius = Radius.circular(layout.cell / 5);
    final fill = Paint();

    for (var index = 0; index < daily.plays.length; index++) {
      fill.color = PlaysHeatmap.shadeColors[shades[index]];
      canvas.drawRRect(RRect.fromRectAndRadius(layout.cellRect(index), radius), fill);
    }

    if (selected != null) {
      final outline = Paint()
        ..color = ThemeColors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRRect(RRect.fromRectAndRadius(layout.cellRect(selected!).deflate(0.75), radius), outline);
    }

    for (final (column, month) in layout.monthLabels()) {
      final text = TextPainter(
        text: TextSpan(text: DateFormat.MMM().format(month), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      // Keep a label over the last columns inside the canvas instead of clipping it.
      final left = (column * layout.pitch).clamp(0.0, size.width - text.width);
      text.paint(canvas, Offset(left, (layout.header - text.height) / 2));
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) {
    return oldDelegate.layout.daily != layout.daily ||
        oldDelegate.layout.cell != layout.cell ||
        oldDelegate.selected != selected ||
        oldDelegate.labelStyle != labelStyle;
  }
}

/// Mon / Wed / Fri next to their rows, outside the scroll view so they stay put.
class _WeekdayGutter extends StatelessWidget {
  static const _labelledRows = [0, 2, 4];

  final _HeatmapLayout layout;
  final TextStyle style;

  const _WeekdayGutter({required this.layout, required this.style});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: ScreenSizeUtil.calculateSize(30),
      height: layout.size.height,
      child: Stack(
        children: [
          for (final row in _labelledRows)
            Positioned(
              top: layout.rowTop(row),
              height: layout.cell,
              left: 0,
              child: Center(
                // 2024-01-01 was a Monday.
                child: Text(DateFormat.E().format(DateTime(2024, 1, 1 + row)), style: style.copyWith(height: 1)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Less ■■■■■ More", one swatch per shade.
class _Legend extends StatelessWidget {
  final double cellSize;
  final TextStyle style;

  const _Legend({required this.cellSize, required this.style});

  @override
  Widget build(BuildContext context) {
    final spacing = ScreenSizeUtil.calculateSize(2);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Less', style: style),
        SizedBox(width: ScreenSizeUtil.calculateSize(4)),
        for (final shade in PlaysHeatmap.shadeColors)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: spacing / 2),
            child: SizedBox.square(
              dimension: cellSize,
              child: DecoratedBox(
                decoration: BoxDecoration(color: shade, borderRadius: BorderRadius.circular(cellSize / 5)),
              ),
            ),
          ),
        SizedBox(width: ScreenSizeUtil.calculateSize(4)),
        Text('More', style: style),
      ],
    );
  }
}
