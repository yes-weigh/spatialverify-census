import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/pdf/hlo_pdf_renderer.dart';
import '../../../core/storage/mission_layout_storage.dart';
import '../models/mission_models.dart';
import '../widgets/hlb_template_sheet_painter.dart';
import 'hlb_export_template_layout.dart';

export 'hlb_export_template_layout.dart' show HlbExportTemplateLayout, resolveHlbExportTemplate, resolveHlbPageSizeFromGeoref;

const kDefaultHlbPageSize = HloPdfPageSize(widthPt: 842, heightPt: 595);

HloPdfPageSize resolveHlbPageSize(Map<String, dynamic>? layoutGeoref) =>
    resolveHlbPageSizeFromGeoref(layoutGeoref);

PdfPageFormat pageFormatFor(HloPdfPageSize size) => PdfPageFormat(
      size.widthPt,
      size.heightPt,
      marginTop: 0,
      marginBottom: 0,
      marginLeft: 0,
      marginRight: 0,
    );

/// Rasterize full sheet: original PDF template + field drawings on map panel.
Future<Uint8List> rasterizeHlbMapPng(
  DraftHlbMap map, {
  required Size size,
  required HlbExportTemplateLayout layout,
  double pixelRatio = 2.5,
}) async {
  ui.Image? templateImage;
  if (layout.hasTemplate && layout.fullSheetPath != null) {
    final bytes = await readMissionLayoutBytes(layout.fullSheetPath!);
    if (bytes != null) {
      templateImage = await decodeUiImageFromBytes(bytes);
    }
  }

  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    HlbTemplateSheetPainter(
      mapData: map,
      templateImage: templateImage,
      sheetInsets: layout.sheetInsets,
      mapPanelRect: layout.mapPanelRect,
      showBoundary: templateImage == null,
    ).paint(canvas, size);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * pixelRatio).round(),
      (size.height * pixelRatio).round(),
    );
    final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (pngBytes == null) throw Exception('Could not render HLB map image');
    return pngBytes.buffer.asUint8List();
  } finally {
    templateImage?.dispose();
  }
}

Future<Uint8List> buildHlbMapPdfBytes({
  required DraftHlbMap map,
  required HlbExportTemplateLayout layout,
}) async {
  const logicalWidth = 1400.0;
  final logicalSize = Size(
    logicalWidth,
    logicalWidth * layout.pageSize.heightPt / layout.pageSize.widthPt,
  );
  final png = await rasterizeHlbMapPng(map, size: logicalSize, layout: layout);

  final doc = pw.Document();
  doc.addPage(
    pw.Page(
      pageFormat: pageFormatFor(layout.pageSize),
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.SizedBox.expand(
        child: pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
      ),
    ),
  );
  return doc.save();
}

Future<void> shareHlbMapPdf({
  required DraftHlbMap map,
  required HlbExportTemplateLayout layout,
}) async {
  final bytes = await buildHlbMapPdfBytes(map: map, layout: layout);
  final safeCode = map.ebCode.replaceAll(RegExp(r'[^\w\-.]+'), '_');
  await Printing.sharePdf(bytes: bytes, filename: 'HLB_$safeCode.pdf');
}

Future<void> shareHlbMapPdfFromState({
  required DraftHlbMap map,
  required Map<String, dynamic>? layoutGeoref,
  required String ebId,
}) async {
  final layout = await resolveHlbExportTemplate(layoutGeoref, ebId);
  await shareHlbMapPdf(map: map, layout: layout);
}
