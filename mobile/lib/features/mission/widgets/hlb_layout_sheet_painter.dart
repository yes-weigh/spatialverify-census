import 'package:flutter/material.dart';

import '../models/hlo_layout_sheet_insets.dart';
import '../models/mission_models.dart';
import 'hlb_map_painter.dart';

/// Paints the census form inside the imported PDF content box, with outer margins white.
class HlbLayoutSheetPainter extends CustomPainter {
  HlbLayoutSheetPainter({
    required this.mapData,
    this.sheetInsets = HloLayoutSheetInsets.fullPageContent,
    this.gaps = const [],
    this.selectedGapId,
    this.highlightGaps = false,
    this.showLegend = true,
    this.showFooter = true,
    this.pageColor = Colors.white,
  });

  final DraftHlbMap mapData;
  final HloLayoutSheetInsets sheetInsets;
  final List<CoverageGap> gaps;
  final String? selectedGapId;
  final bool highlightGaps;
  final bool showLegend;
  final bool showFooter;
  final Color pageColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);

    final contentRect = sheetInsets.contentRect(size);
    canvas.save();
    canvas.clipRect(contentRect);
    canvas.translate(contentRect.left, contentRect.top);
    HlbMapPainter(
      mapData: mapData,
      gaps: gaps,
      selectedGapId: selectedGapId,
      highlightGaps: highlightGaps,
      showLegend: showLegend,
      showFooter: showFooter,
    ).paint(canvas, contentRect.size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HlbLayoutSheetPainter old) =>
      old.mapData != mapData ||
      old.sheetInsets != sheetInsets ||
      old.gaps != gaps ||
      old.selectedGapId != selectedGapId ||
      old.highlightGaps != highlightGaps ||
      old.showLegend != showLegend ||
      old.showFooter != showFooter ||
      old.pageColor != pageColor;
}
