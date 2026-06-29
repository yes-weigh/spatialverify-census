import 'package:flutter/material.dart';

/// Normalized placement of the census form on the imported HLO sheet (0–1).
///
/// Outer page area outside this rect is the white margin copied from the PDF.
class HloLayoutSheetInsets {
  const HloLayoutSheetInsets({
    required this.contentLeft,
    required this.contentTop,
    required this.contentWidth,
    required this.contentHeight,
  });

  final double contentLeft;
  final double contentTop;
  final double contentWidth;
  final double contentHeight;

  static const fullPageContent = HloLayoutSheetInsets(
    contentLeft: 0,
    contentTop: 0,
    contentWidth: 1,
    contentHeight: 1,
  );

  factory HloLayoutSheetInsets.fromPixels({
    required int pageWidth,
    required int pageHeight,
    required int left,
    required int top,
    required int width,
    required int height,
  }) {
    if (pageWidth <= 0 || pageHeight <= 0) return fullPageContent;
    return HloLayoutSheetInsets(
      contentLeft: left / pageWidth,
      contentTop: top / pageHeight,
      contentWidth: width / pageWidth,
      contentHeight: height / pageHeight,
    );
  }

  factory HloLayoutSheetInsets.fromJson(Map<String, dynamic> json) {
    final left = (json['contentLeft'] as num?)?.toDouble();
    final top = (json['contentTop'] as num?)?.toDouble();
    final width = (json['contentWidth'] as num?)?.toDouble();
    final height = (json['contentHeight'] as num?)?.toDouble();
    if (left == null || top == null || width == null || height == null) {
      return fullPageContent;
    }
    if (width <= 0 || height <= 0) return fullPageContent;
    return HloLayoutSheetInsets(
      contentLeft: left.clamp(0, 1),
      contentTop: top.clamp(0, 1),
      contentWidth: width.clamp(0, 1),
      contentHeight: height.clamp(0, 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'contentLeft': contentLeft,
        'contentTop': contentTop,
        'contentWidth': contentWidth,
        'contentHeight': contentHeight,
      };

  Rect contentRect(Size pageSize) => Rect.fromLTWH(
        pageSize.width * contentLeft,
        pageSize.height * contentTop,
        pageSize.width * contentWidth,
        pageSize.height * contentHeight,
      );

  bool get hasOuterMargin =>
      contentLeft > 0.001 ||
      contentTop > 0.001 ||
      contentLeft + contentWidth < 0.999 ||
      contentTop + contentHeight < 0.999;
}

HloLayoutSheetInsets resolveHlbLayoutSheetInsets(Map<String, dynamic>? layoutGeoref) {
  final raw = layoutGeoref?['sourceLayoutInsets'];
  if (raw is Map) {
    return HloLayoutSheetInsets.fromJson(Map<String, dynamic>.from(raw));
  }
  return HloLayoutSheetInsets.fullPageContent;
}
