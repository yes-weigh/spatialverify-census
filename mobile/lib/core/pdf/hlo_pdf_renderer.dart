import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';

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
