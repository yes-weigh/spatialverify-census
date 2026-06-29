import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/spatial_cv/spatial_cv_image.dart';
import '../models/landmark_anchor_models.dart';

/// Reads place/road names printed on the HLO satellite panel (excludes metadata sidebar).
class MapPanelOcrService {
  MapPanelOcrService({TextRecognizer? recognizer})
      : _recognizer = recognizer ?? TextRecognizer(script: TextRecognitionScript.latin);

  final TextRecognizer _recognizer;
  static const _uuid = Uuid();

  /// Left fraction of page reserved for Census metadata panel — skip for structure OCR.
  static const sidebarFraction = kHloLayoutSidebarFraction;

  int _panelLeft(img.Image decoded) =>
      detectHloSatellitePanelOnly(decoded)
          ? 0
          : (decoded.width * sidebarFraction).round().clamp(0, decoded.width - 1);

  Future<List<MapTextLabel>> extractLabels(Uint8List imageBytes) async {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return [];

    final panelLeft = _panelLeft(decoded);
    final panel = img.copyCrop(
      decoded,
      x: panelLeft,
      y: 0,
      width: decoded.width - panelLeft,
      height: decoded.height,
    );

    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/hlo_ocr_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(tempPath).writeAsBytes(img.encodePng(panel));

    try {
      final recognized = await _recognizer.processImage(InputImage.fromFilePath(tempPath));
      final labels = <MapTextLabel>[];

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = _cleanLine(line.text);
          if (!_isUsefulMapLabel(text)) continue;

          final box = line.boundingBox;
          final cx = box.left + box.width / 2;
          final cy = box.top + box.height / 2;
          final fullX = panelLeft + cx;
          final uvX = (fullX / decoded.width).clamp(0.0, 1.0);
          final uvY = (cy / decoded.height).clamp(0.0, 1.0);

          labels.add(MapTextLabel(
            id: _uuid.v4(),
            text: text,
            uvX: uvX,
            uvY: uvY,
          ));
        }
      }

      return _dedupeLabels(labels);
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }

  /// Locates the printed EB block number (e.g. 0595) on the map panel for boundary detection.
  Future<({double x, double y})?> findEbBlockCenter(Uint8List imageBytes, String ebNo) async {
    final normalizedEb = ebNo.replaceFirst(RegExp(r'^0+'), '');
    if (normalizedEb.isEmpty) return null;

    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final panelLeft = _panelLeft(decoded);
    final panel = img.copyCrop(
      decoded,
      x: panelLeft,
      y: 0,
      width: decoded.width - panelLeft,
      height: decoded.height,
    );

    final tempDir = await getTemporaryDirectory();
    final tempPath = '${tempDir.path}/hlo_eb_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(tempPath).writeAsBytes(img.encodePng(panel));

    try {
      final recognized = await _recognizer.processImage(InputImage.fromFilePath(tempPath));
      ({double x, double y})? best;
      var bestLen = 999;

      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          final text = _cleanLine(line.text);
          final digits = text.replaceAll(RegExp(r'\D'), '');
          if (digits.isEmpty) continue;
          final normalized = digits.replaceFirst(RegExp(r'^0+'), '');
          if (normalized != normalizedEb && digits != ebNo) continue;

          final box = line.boundingBox;
          final cx = panelLeft + box.left + box.width / 2;
          final candidate = (
            x: (cx / decoded.width).clamp(0.0, 1.0),
            y: ((box.top + box.height / 2) / decoded.height).clamp(0.0, 1.0),
          );
          if (text.length < bestLen) {
            best = candidate;
            bestLen = text.length;
          }
        }
      }
      return best;
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await _recognizer.close();
  }

  static String _cleanLine(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Census PDF chrome / OSM attribution — not geocodable landmarks.
  static String _normalizeForMatch(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isMapTemplateText(String text) {
    final n = _normalizeForMatch(text);
    if (n.isEmpty) return true;

    const containsAny = [
      'openstreet',
      'open street map',
      'openstreetmap',
      'contributor',
      'contbutor',
      'houselisting',
      'housing census',
      'house listing',
      'official purpose',
      'pupose oniy',
      'pupose only',
      'purpose oniy',
      'purpose only',
      'for official',
      'official census',
      'census document',
      'to be used for',
      'important census',
    ];
    for (final phrase in containsAny) {
      if (n.contains(phrase)) return true;
    }

    // OCR fragments of the footer disclaimer.
    if (RegExp(r'\bpupose\b').hasMatch(n)) return true;
    if (n.contains('oniy') && (n.contains('pupose') || n.contains('purpose') || n.contains('official'))) {
      return true;
    }

    return false;
  }

  static bool _isUsefulMapLabel(String text) {
    if (text.length < 4 || text.length > 48) return false;
    if (RegExp(r'^\d+$').hasMatch(text)) return false;
    if (_isMapTemplateText(text)) return false;

    final lower = text.toLowerCase();
    const skip = [
      'district name',
      'sub-district',
      'sub district',
      'town/village',
      'ward no',
      'eb no',
      'enumerator block',
      'compiled by',
      'census of india',
      'layout map',
      'code no',
      'generated on',
      'area statement',
      'legend',
      'north',
      'scale',
      'hlb',
      'map generated',
    ];
    for (final s in skip) {
      if (lower.contains(s)) return false;
    }

    const keepHints = [
      'road',
      ' rd',
      'street',
      ' st',
      'lane',
      'nagar',
      'school',
      'college',
      'temple',
      'church',
      'mosque',
      'hospital',
      'junction',
      'market',
      'bridge',
      'canal',
      'nh ',
      'nh-',
      'island',
      'club',
      'park',
      'station',
      'metro',
      'mall',
      'hotel',
      'bank',
      'post office',
    ];
    if (keepHints.any(lower.contains)) return true;

    // Title-case labels on maps (e.g. Vyttila, Aluva, Silversand)
    if (RegExp(r'^[A-Z][a-zA-Z0-9\s\-/]{2,}$').hasMatch(text)) return true;
    if (RegExp(r'^[A-Z]{2,}[a-z]*(?:\s+[A-Z]{2,}[a-z]*)*$').hasMatch(text)) return true;

    return text.split(' ').length >= 2;
  }

  static List<MapTextLabel> _dedupeLabels(List<MapTextLabel> labels) {
    final out = <MapTextLabel>[];
    for (final label in labels) {
      final dup = out.indexWhere(
        (o) => o.text.toLowerCase() == label.text.toLowerCase() ||
            (o.text.toLowerCase().contains(label.text.toLowerCase()) && label.text.length > 6),
      );
      if (dup >= 0) continue;
      out.add(label);
    }
    out.sort((a, b) => b.text.length.compareTo(a.text.length));
    return out.take(12).toList();
  }
}
