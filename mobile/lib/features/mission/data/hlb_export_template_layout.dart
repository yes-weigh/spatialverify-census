import '../../../core/pdf/hlo_pdf_renderer.dart';
import '../../../core/storage/mission_layout_storage.dart';
import '../models/hlo_layout_sheet_insets.dart';
import '../models/hlo_map_panel_rect.dart';

class HlbExportTemplateLayout {
  const HlbExportTemplateLayout({
    required this.pageSize,
    required this.sheetInsets,
    required this.mapPanelRect,
    this.fullSheetPath,
  });

  final HloPdfPageSize pageSize;
  final HloLayoutSheetInsets sheetInsets;
  final HloMapPanelRect mapPanelRect;
  final String? fullSheetPath;

  bool get hasTemplate => fullSheetPath != null;
}

Future<HlbExportTemplateLayout> resolveHlbExportTemplate(
  Map<String, dynamic>? layoutGeoref,
  String ebId,
) async {
  var fullSheetPath = layoutGeoref?['sourceFullSheetPath'] as String?;
  if (fullSheetPath == null || !await missionLayoutExists(fullSheetPath)) {
    fullSheetPath = await defaultMissionFullSheetRef(ebId);
    if (fullSheetPath != null && !await missionLayoutExists(fullSheetPath)) {
      fullSheetPath = null;
    }
  }

  return HlbExportTemplateLayout(
    pageSize: resolveHlbPageSizeFromGeoref(layoutGeoref),
    sheetInsets: resolveHlbLayoutSheetInsets(layoutGeoref),
    mapPanelRect: resolveHlbMapPanelRect(layoutGeoref),
    fullSheetPath: fullSheetPath,
  );
}

HloPdfPageSize resolveHlbPageSizeFromGeoref(Map<String, dynamic>? layoutGeoref) {
  final stored = layoutGeoref?['sourcePageSizePt'];
  if (stored is Map) {
    final parsed = HloPdfPageSize.fromJson(Map<String, dynamic>.from(stored));
    if (parsed != null) return parsed;
  }
  return const HloPdfPageSize(widthPt: 842, heightPt: 595);
}
