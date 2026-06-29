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
  final _enumNameCtrl = TextEditingController();
  final _enumDateCtrl = TextEditingController();
  final _supNameCtrl = TextEditingController();
  final _supDateCtrl = TextEditingController();
  var _footerLoaded = false;

  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void dispose() {
    _enumNameCtrl.dispose();
    _enumDateCtrl.dispose();
    _supNameCtrl.dispose();
    _supDateCtrl.dispose();
    super.dispose();
  }

  void _loadFooter(DraftHlbMap map) {
    if (_footerLoaded) return;
    final f = map.footerBlock;
    _enumNameCtrl.text = f.enumeratorName ?? '';
    _enumDateCtrl.text = f.enumeratorDate ?? _today();
    _supNameCtrl.text = f.supervisorName ?? '';
    _supDateCtrl.text = f.supervisorDate ?? '';
    _footerLoaded = true;
  }

  String _today() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
  }

  Future<void> _saveFooter() async {
    final local = ref.read(missionLocalFirstProvider);
    await local.saveLayoutMapFooter(
      widget.ebId,
      enumeratorName: _enumNameCtrl.text.trim().isEmpty ? null : _enumNameCtrl.text.trim(),
      enumeratorDate: _enumDateCtrl.text.trim().isEmpty ? null : _enumDateCtrl.text.trim(),
      supervisorName: _supNameCtrl.text.trim().isEmpty ? null : _supNameCtrl.text.trim(),
      supervisorDate: _supDateCtrl.text.trim().isEmpty ? null : _supDateCtrl.text.trim(),
    );
    ref.invalidate(draftMapProvider(_query));
  }

  Future<void> _exportPdf(DraftHlbMap map) async {
    await _saveFooter();
    if (!mounted) return;
    final mapAsync = await ref.read(draftMapProvider(_query).future);
    final boundary = await _captureMap();
    if (boundary == null || !mounted) return;

    final title = mapAsync.titleBlock;
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(14),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'CENSUS OF INDIA — LAYOUT MAP (HOUSE LISTING BLOCK)',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            if (title != null) ...[
              pw.SizedBox(height: 4),
              ...title.lines.map((l) => pw.Text(l, style: const pw.TextStyle(fontSize: 8))),
            ],
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.Center(child: pw.Image(pw.MemoryImage(boundary), fit: pw.BoxFit.contain)),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Enumerator', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text('Name: ${_enumNameCtrl.text.isEmpty ? '________' : _enumNameCtrl.text}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Date: ${_enumDateCtrl.text}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Signature: ________________', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Supervisor', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text('Name: ${_supNameCtrl.text.isEmpty ? '________' : _supNameCtrl.text}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Date: ${_supDateCtrl.text}', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('Signature: ________________', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Text(HlbOfficialCatalog.legendLine(), style: const pw.TextStyle(fontSize: 7)),
            pw.Text(
              'Buildings: ${mapAsync.buildings.length}  |  Features: ${mapAsync.landmarks.length}  |  Lines: ${mapAsync.lineFeatures.length}  |  Labels: ${mapAsync.annotations.length}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  Future<Uint8List?> _captureMap() async {
    final renderObject = _mapKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return null;
    final image = await renderObject.toImage(pixelRatio: 2.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(draftMapProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft HLB Map'),
        actions: [
          mapAsync.maybeWhen(
            data: (map) => IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Export official PDF',
              onPressed: () => _exportPdf(map),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: mapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (map) {
          _loadFooter(map);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              RepaintBoundary(
                key: _mapKey,
                child: AspectRatio(
                  aspectRatio: 1.1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CustomPaint(
                        painter: HlbMapPainter(mapData: map, showFooter: true),
                        size: Size.infinite,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Enumerator & supervisor (footer)', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _enumNameCtrl,
                decoration: const InputDecoration(labelText: 'Enumerator name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _enumDateCtrl,
                decoration: const InputDecoration(labelText: 'Enumerator date', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _supNameCtrl,
                decoration: const InputDecoration(labelText: 'Supervisor name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _supDateCtrl,
                decoration: const InputDecoration(labelText: 'Supervisor date', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saveFooter,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save footer on map'),
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
              if (map.startPoint != null)
                Text(
                  'Start: Bldg ${map.startPoint!.buildingNumber ?? '?'}  ·  End: Bldg ${map.endPoint?.buildingNumber ?? '?'}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              if (map.buildings.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Walk your HLB and confirm buildings — the layout map fills from GPS marks.',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to mission map'),
              ),
            ],
          );
        },
      ),
    );
  }
}
