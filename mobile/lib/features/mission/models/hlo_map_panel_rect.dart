import 'package:flutter/material.dart';

import 'hlo_layout_sheet_insets.dart';

/// Normalized map-panel region within the trimmed census form (0–1).
class HloMapPanelRect {
  const HloMapPanelRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  static const fullForm = HloMapPanelRect(
    left: 0.28,
    top: 0.11,
    width: 0.70,
    height: 0.78,
  );

  factory HloMapPanelRect.fromPixels({
    required int formWidth,
    required int formHeight,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    if (formWidth <= 0 || formHeight <= 0) return fullForm;
    return HloMapPanelRect(
      left: left / formWidth,
      top: top / formHeight,
      width: width / formWidth,
      height: height / formHeight,
    );
  }

  factory HloMapPanelRect.fromJson(Map<String, dynamic> json) {
    final left = (json['left'] as num?)?.toDouble();
    final top = (json['top'] as num?)?.toDouble();
    final width = (json['width'] as num?)?.toDouble();
    final height = (json['height'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null) {
      return fullForm;
    }
    return HloMapPanelRect(
      left: left.clamp(0, 1),
      top: top.clamp(0, 1),
      width: width.clamp(0, 1),
      height: height.clamp(0, 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  /// Map panel on the full PDF page (content insets + panel within form).
  Rect rectOnPage(Size pageSize, HloLayoutSheetInsets sheetInsets) {
    final content = sheetInsets.contentRect(pageSize);
    return Rect.fromLTWH(
      content.left + left * content.width,
      content.top + top * content.height,
      width * content.width,
      height * content.height,
    );
  }
}

HloMapPanelRect resolveHlbMapPanelRect(Map<String, dynamic>? layoutGeoref) {
  final raw = layoutGeoref?['sourceMapPanelRect'];
  if (raw is Map) {
    return HloMapPanelRect.fromJson(Map<String, dynamic>.from(raw));
  }
  return HloMapPanelRect.fullForm;
}
