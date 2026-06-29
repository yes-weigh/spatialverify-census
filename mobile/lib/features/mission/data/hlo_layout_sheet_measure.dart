import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../../core/spatial_cv/spatial_cv_image.dart';
import '../models/hlo_layout_sheet_insets.dart';
import '../models/hlo_map_panel_rect.dart';

/// Measures where the census form sits on the imported PDF page (outer margins preserved).
HloLayoutSheetInsets measureHloLayoutSheetInsets(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return HloLayoutSheetInsets.fullPageContent;

  final bounds = detectLayoutContentBounds(decoded);
  if (bounds == null) return HloLayoutSheetInsets.fullPageContent;

  return HloLayoutSheetInsets.fromPixels(
    pageWidth: decoded.width,
    pageHeight: decoded.height,
    left: bounds.left,
    top: bounds.top,
    width: bounds.width,
    height: bounds.height,
  );
}

/// Satellite map panel within the trimmed form (excludes left metadata column).
HloMapPanelRect measureMapPanelRect(Uint8List fullPageBytes) {
  final decoded = img.decodeImage(fullPageBytes);
  if (decoded == null) return HloMapPanelRect.fullForm;

  final bounds = detectLayoutContentBounds(decoded);
  final form = bounds == null
      ? decoded
      : img.copyCrop(
          decoded,
          x: bounds.left,
          y: bounds.top,
          width: bounds.width,
          height: bounds.height,
        );

  final sidebarW = (form.width * kHloLayoutSidebarFraction).round().clamp(0, form.width - 80);
  const pad = 2;
  final titleBand = (form.height * 0.11).round();
  final footerBand = (form.height * 0.09).round();
  final mapLeft = sidebarW + pad;
  final mapTop = titleBand + pad;
  final mapWidth = (form.width - mapLeft - pad).clamp(40, form.width);
  final mapHeight = (form.height - mapTop - footerBand - pad).clamp(40, form.height);

  return HloMapPanelRect.fromPixels(
    formWidth: form.width,
    formHeight: form.height,
    left: mapLeft,
    top: mapTop,
    width: mapWidth,
    height: mapHeight,
  );
}
