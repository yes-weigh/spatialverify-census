import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';

/// Physical page size of an HLO PDF in PDF points (1/72 inch).
class HloPdfPageSize {
  const HloPdfPageSize({required this.widthPt, required this.heightPt});

  final double widthPt;
  final double heightPt;

  Map<String, dynamic> toJson() => {'width': widthPt, 'height': heightPt};

  static HloPdfPageSize? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final w = (json['width'] as num?)?.toDouble();
    final h = (json['height'] as num?)?.toDouble();
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return HloPdfPageSize(widthPt: w, heightPt: h);
  }
}

/// Reads page 1 dimensions from an HLO PDF (points).
Future<HloPdfPageSize?> readHloPdfPageSizePt(Uint8List pdfBytes) async {
  if (kIsWeb) return null;

  final doc = await PdfDocument.openData(pdfBytes);
  try {
    final page = await doc.getPage(1);
    try {
      return HloPdfPageSize(widthPt: page.width, heightPt: page.height);
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}

/// Rasterize page 1 of an HLO PDF to PNG bytes (web + mobile).
Future<Uint8List> renderHloPdfPagePng(Uint8List pdfBytes) async {
  if (kIsWeb) {
    // pdf.js module scripts in index.html need a moment before first raster call.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final pages = await Printing.raster(
      pdfBytes,
      pages: [0],
      dpi: 120,
    ).toList().timeout(
      const Duration(seconds: 90),
      onTimeout: () => throw TimeoutException(
        'PDF rendering timed out — refresh the page and try again',
      ),
    );
    if (pages.isEmpty) {
      throw Exception('Could not render PDF page');
    }
    return pages.first.toPng();
  }

  final doc = await PdfDocument.openData(pdfBytes);
  try {
    final page = await doc.getPage(1);
    try {
      final rendered = await page.render(
        width: (page.width * 2).toDouble(),
        height: (page.height * 2).toDouble(),
        format: PdfPageImageFormat.png,
      );
      if (rendered == null) throw Exception('Could not render PDF page');
      return rendered.bytes;
    } finally {
      await page.close();
    }
  } finally {
    await doc.close();
  }
}
