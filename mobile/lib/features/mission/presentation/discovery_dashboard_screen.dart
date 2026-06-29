import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/hlb_local_state.dart';
import '../data/mission_local_first_service.dart';
import '../models/mission_models.dart';
import '../widgets/hlb_map_painter.dart';
import 'mission_providers.dart';

/// Discovery dashboard — 2D map + pseudo-3D spatial visualization.
class DiscoveryDashboardScreen extends ConsumerWidget {
  const DiscoveryDashboardScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  EbMissionQuery get _query => EbMissionQuery(ebId: ebId, projectId: projectId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(_query));
    final mapAsync = ref.watch(draftMapProvider(_query));
    final local = ref.watch(missionLocalFirstProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        title: const Text('Discovery Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => context.push('/mission/$projectId/eb/$ebId/discover-walk'),
          ),
        ],
      ),
      body: discoveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) => FutureBuilder<HlbLocalState?>(
          future: local.getRawState(ebId),
          builder: (context, snap) {
            final nodes = snap.data?.spatialNodes ?? [];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StatsHeader(discovery: d),
                const SizedBox(height: 20),
                const Text('2D HLB Map', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                mapAsync.when(
                  loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                  error: (e, _) => Text('$e'),
                  data: (map) => AspectRatio(
                    aspectRatio: 4 / 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CustomPaint(painter: HlbMapPainter(mapData: map, highlightGaps: false)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Spatial Scan View', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text('${nodes.length} observations', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'GPS + heading blocks — discovery visualization, not photogrammetry.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: _Pseudo3DView(
                    buildings: d.buildingsDiscovered,
                    mapAsync: mapAsync,
                    nodes: nodes,
                  ),
                ),
                const SizedBox(height: 20),
                _CompletionEstimate(discovery: d),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  const _StatsHeader({required this.discovery});
  final DiscoveryStatus discovery;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip('Boundary', '${discovery.boundaryCoveragePercent}%'),
        _Chip('Road', '${discovery.roadCoveragePercent}%'),
        _Chip('Buildings', '${discovery.buildingsDiscovered}'),
        _Chip('Landmarks', '${discovery.landmarksDiscovered}'),
        if (discovery.hasOfficialBoundary) const _Chip('Source', 'Official'),
        _Chip('Gaps', '${discovery.gapSummary.open}'),
        _Chip('Confidence', discovery.gapSummary.open == 0 ? 'High' : 'Review'),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      ),
    );
  }
}

class _Pseudo3DView extends StatelessWidget {
  const _Pseudo3DView({required this.buildings, required this.mapAsync, required this.nodes});
  final int buildings;
  final AsyncValue<DraftHlbMap> mapAsync;
  final List<LocalSpatialNode> nodes;

  @override
  Widget build(BuildContext context) {
    return mapAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (map) => CustomPaint(
        painter: _Pseudo3DPainter(buildings: map.buildings, nodes: nodes),
        size: Size.infinite,
      ),
    );
  }
}

class _Pseudo3DPainter extends CustomPainter {
  _Pseudo3DPainter({required this.buildings, required this.nodes});
  final List<DraftMapBuilding> buildings;
  final List<LocalSpatialNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF12121F));

    if (buildings.isEmpty) {
      _drawText(canvas, 'Walk and confirm buildings to populate spatial view', Offset(size.width / 2 - 120, size.height / 2), 12);
      return;
    }

    final cx = size.width / 2;
    final cy = size.height * 0.65;
    const scale = 180.0;

    for (final b in buildings) {
      final dx = (b.mapX - 0.5) * scale;
      final dy = (b.mapY - 0.5) * scale;
      final h = 12.0 + (b.censusHouseCount * 6);
      _drawBlock(canvas, Offset(cx + dx, cy + dy), 14, h, const Color(0xFF42A5F5));
    }

    for (final n in nodes) {
      if (n.type == 'landmark') {
        canvas.drawCircle(Offset(cx, cy - 40), 5, Paint()..color = const Color(0xFFCE93D8));
      }
    }

    _drawText(canvas, 'N', Offset(size.width - 24, 12), 11);
  }

  void _drawBlock(Canvas canvas, Offset base, double w, double h, Color color) {
    final path = Path()
      ..moveTo(base.dx, base.dy)
      ..lineTo(base.dx + w * 0.5, base.dy - h * 0.3)
      ..lineTo(base.dx + w * 0.5, base.dy - h - h * 0.3)
      ..lineTo(base.dx, base.dy - h)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  void _drawText(Canvas canvas, String t, Offset o, double sz) {
    TextPainter(text: TextSpan(text: t, style: TextStyle(color: Colors.white54, fontSize: sz)), textDirection: TextDirection.ltr)
      ..layout()
      ..paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _Pseudo3DPainter old) => old.buildings != buildings;
}

class _CompletionEstimate extends StatelessWidget {
  const _CompletionEstimate({required this.discovery});
  final DiscoveryStatus discovery;

  @override
  Widget build(BuildContext context) {
    final boundary = discovery.boundaryCoveragePercent;
    final road = discovery.roadCoveragePercent;
    final gaps = discovery.gapSummary.open;
    final est = ((boundary * 0.35 + road * 0.45 + (gaps == 0 ? 20 : 0)).clamp(0, 100)).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Estimated HLB Completion', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: est / 100, minHeight: 8, borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 8),
          Text('$est% — boundary, road coverage, and open gaps', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}
