import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/storage/mission_layout_storage.dart';
import '../data/hlb_export_template_layout.dart';
import '../models/mission_models.dart';
import 'hlb_template_sheet_painter.dart';

/// Preview: original imported PDF (left panel + borders) with field drawings on map panel.
class HlbTemplateSheetPreview extends StatefulWidget {
  const HlbTemplateSheetPreview({
    required this.mapData,
    required this.layout,
    this.showBoundary = true,
    this.showBuildings = true,
    this.showLandmarks = true,
    this.showLineFeatures = true,
    this.showWalkPath = true,
    this.showEndpoints = true,
    super.key,
  });

  final DraftHlbMap mapData;
  final HlbExportTemplateLayout layout;
  final bool showBoundary;
  final bool showBuildings;
  final bool showLandmarks;
  final bool showLineFeatures;
  final bool showWalkPath;
  final bool showEndpoints;

  @override
  State<HlbTemplateSheetPreview> createState() => _HlbTemplateSheetPreviewState();
}

class _HlbTemplateSheetPreviewState extends State<HlbTemplateSheetPreview> {
  ui.Image? _templateImage;
  var _loading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplate();
  }

  @override
  void didUpdateWidget(covariant HlbTemplateSheetPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout.fullSheetPath != widget.layout.fullSheetPath) {
      _loadTemplate();
    }
  }

  @override
  void dispose() {
    _templateImage?.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    final path = widget.layout.fullSheetPath;
    _templateImage?.dispose();
    _templateImage = null;
    if (path == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final bytes = await readMissionLayoutBytes(path);
    ui.Image? image;
    if (bytes != null) {
      image = await decodeUiImageFromBytes(bytes);
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _templateImage = image;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return CustomPaint(
      painter: HlbTemplateSheetPainter(
        mapData: widget.mapData,
        templateImage: _templateImage,
        sheetInsets: widget.layout.sheetInsets,
        mapPanelRect: widget.layout.mapPanelRect,
        showBoundary: widget.showBoundary,
        showBuildings: widget.showBuildings,
        showLandmarks: widget.showLandmarks,
        showLineFeatures: widget.showLineFeatures,
        showWalkPath: widget.showWalkPath,
        showEndpoints: widget.showEndpoints,
      ),
      size: Size.infinite,
    );
  }
}
