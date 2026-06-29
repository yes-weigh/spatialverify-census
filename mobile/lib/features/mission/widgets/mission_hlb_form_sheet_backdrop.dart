import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mission_map_style.dart';
import '../presentation/mission_providers.dart';
import 'hlb_template_sheet_preview.dart';

/// Full-screen original PDF form (left panel + borders) when satellite and PDF overlay are off.
class MissionHlbFormSheetBackdrop extends ConsumerWidget {
  const MissionHlbFormSheetBackdrop({
    required this.query,
    this.showBoundary = true,
    this.showBuildings = true,
    this.showLineFeatures = true,
    this.showWalkPath = true,
    super.key,
  });

  final EbMissionQuery query;
  final bool showBoundary;
  final bool showBuildings;
  final bool showLineFeatures;
  final bool showWalkPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mapAsync = ref.watch(draftMapProvider(query));
    final templateAsync = ref.watch(hlbExportTemplateProvider(query));

    return ColoredBox(
      color: MissionMapStyle.basemapOffBackground,
      child: mapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (_, __) => const SizedBox.shrink(),
        data: (map) => templateAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          error: (_, __) => const SizedBox.shrink(),
          data: (layout) {
            final aspect = layout.pageSize.widthPt / layout.pageSize.heightPt;
            return LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final maxH = constraints.maxHeight;
                late final double sheetW;
                late final double sheetH;
                if (maxW / maxH > aspect) {
                  sheetH = maxH;
                  sheetW = maxH * aspect;
                } else {
                  sheetW = maxW;
                  sheetH = maxW / aspect;
                }
                return Center(
                  child: SizedBox(
                    width: sheetW,
                    height: sheetH,
                    child: HlbTemplateSheetPreview(
                      mapData: map,
                      layout: layout,
                      showBoundary: showBoundary,
                      showBuildings: showBuildings,
                      showLandmarks: showBuildings,
                      showLineFeatures: showLineFeatures,
                      showWalkPath: showWalkPath,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
