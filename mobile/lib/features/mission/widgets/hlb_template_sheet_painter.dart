import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/hlo_layout_sheet_insets.dart';
import '../models/hlo_map_panel_rect.dart';
import '../models/mission_models.dart';
import 'hlb_map_panel_painter.dart';
import 'hlb_map_painter.dart';

/// Original imported PDF as background + field drawings on the map panel.
class HlbTemplateSheetPainter extends CustomPainter {
  HlbTemplateSheetPainter({
    required this.mapData,
    this.templateImage,
    this.sheetInsets = HloLayoutSheetInsets.fullPageContent,
    this.mapPanelRect = HloMapPanelRect.fullForm,
    this.gaps = const [],
    this.selectedGapId,
    this.highlightGaps = false,
    this.pageColor = Colors.white,
    this.showBoundary = true,
    this.showBuildings = true,
    this.showLandmarks = true,
    this.showLineFeatures = true,
    this.showWalkPath = true,
    this.showEndpoints = true,
  });

  final DraftHlbMap mapData;
  final ui.Image? templateImage;
  final HloLayoutSheetInsets sheetInsets;
  final HloMapPanelRect mapPanelRect;
  final List<CoverageGap> gaps;
  final String? selectedGapId;
  final bool highlightGaps;
  final Color pageColor;
  final bool showBoundary;
  final bool showBuildings;
  final bool showLandmarks;
  final bool showLineFeatures;
  final bool showWalkPath;
  final bool showEndpoints;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = pageColor);

    if (templateImage != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        templateImage!.width.toDouble(),
        templateImage!.height.toDouble(),
      );
      canvas.drawImageRect(templateImage!, src, Offset.zero & size, Paint());
    } else {
      final contentRect = sheetInsets.contentRect(size);
      canvas.save();
      canvas.clipRect(contentRect);
      canvas.translate(contentRect.left, contentRect.top);
      HlbMapPainter(
        mapData: mapData,
        gaps: gaps,
        selectedGapId: selectedGapId,
        highlightGaps: highlightGaps,
        showLegend: true,
        showFooter: true,
      ).paint(canvas, contentRect.size);
      canvas.restore();
      return;
    }

    final panelRect = mapPanelRect.rectOnPage(size, sheetInsets);
    canvas.save();
    canvas.clipRect(panelRect);
    canvas.translate(panelRect.left, panelRect.top);
    HlbMapPanelPainter(
      mapData: mapData,
      gaps: gaps,
      selectedGapId: selectedGapId,
      highlightGaps: highlightGaps,
      showBoundary: showBoundary,
      showBuildings: showBuildings,
      showLandmarks: showLandmarks,
      showLineFeatures: showLineFeatures,
      showWalkPath: showWalkPath,
      showEndpoints: showEndpoints,
    ).paint(canvas, panelRect.size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant HlbTemplateSheetPainter old) =>
      old.mapData != mapData ||
      old.templateImage != templateImage ||
      old.sheetInsets != sheetInsets ||
      old.mapPanelRect != mapPanelRect ||
      old.gaps != gaps ||
      old.selectedGapId != selectedGapId ||
      old.highlightGaps != highlightGaps ||
      old.pageColor != pageColor ||
      old.showBoundary != showBoundary ||
      old.showBuildings != showBuildings ||
      old.showLandmarks != showLandmarks ||
      old.showLineFeatures != showLineFeatures ||
      old.showWalkPath != showWalkPath ||
      old.showEndpoints != showEndpoints;
}

Future<ui.Image?> decodeUiImageFromBytes(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  final frame = await codec.getNextFrame();
  return frame.image;
}
