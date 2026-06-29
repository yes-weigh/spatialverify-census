import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';
import '../data/hlb_official_catalog.dart';
import '../widgets/hlb_map_painter.dart';
import 'mission_providers.dart';

class DraftHlbMapScreen extends ConsumerStatefulWidget {
  const DraftHlbMapScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<DraftHlbMapScreen> createState() => _DraftHlbMapScreenState();
}

class _DraftHlbMapScreenState extends ConsumerState<DraftHlbMapScreen> {
  final _mapKey = GlobalKey();

  Future<void> _exportPdf(DraftHlbMap map) async {
    final boundary = await _captureMap();
    if (boundary == null || !mounted) return;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('House Listing Block — ${map.ebCode}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Draft HLB Map (for review and correction)', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 8),
            pw.Expanded(
              child: pw.Center(child: pw.Image(pw.MemoryImage(boundary), fit: pw.BoxFit.contain)),
            ),
            pw.SizedBox(height: 8),
            pw.Text(HlbOfficialCatalog.legendLine(), style: const pw.TextStyle(fontSize: 9)),
            pw.Text(HlbOfficialCatalog.compactLegendFeatures(), style: const pw.TextStyle(fontSize: 8)),
            pw.Text('Buildings: ${map.buildings.length}  |  Landmarks: ${map.landmarks.length}', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<Uint8List?> _captureMap() async {
    final renderObject = _mapKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(draftMapProvider(EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId)));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft HLB Map'),
        actions: [
          mapAsync.maybeWhen(
            data: (map) => IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export PDF',
              onPressed: () => _exportPdf(map),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: mapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (map) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            RepaintBoundary(
              key: _mapKey,
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: HlbMapPainter(mapData: map),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Serpentine order (NW → SE)', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in map.serpentineOrder)
                  Chip(label: Text(e.label, style: const TextStyle(fontSize: 11))),
              ],
            ),
            if (map.buildings.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Text(
                  'Walk your HLB and confirm buildings — the draft map fills in from GPS.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Discovery'),
            ),
          ],
        ),
      ),
    );
  }
}
