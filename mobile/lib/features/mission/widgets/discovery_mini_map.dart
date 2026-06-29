import 'package:flutter/material.dart';

import '../data/discovery_analytics.dart';
import '../models/mission_models.dart';
import 'discovery_heatmap_painter.dart';

/// Live discovery heatmap — where to walk next, without opening gap investigation.
class DiscoveryMiniMap extends StatelessWidget {
  const DiscoveryMiniMap({
    required this.mapData,
    required this.heatmapCells,
    this.streets = const [],
    this.onTap,
    this.onExpand,
    super.key,
  });

  final DraftHlbMap mapData;
  final List<HeatmapCell> heatmapCells;
  final List<StreetSegment> streets;
  final VoidCallback? onTap;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: const Color(0xFF1A1A2E),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 150,
          height: 118,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CustomPaint(
                  painter: DiscoveryHeatmapPainter(
                    mapData: mapData,
                    heatmapCells: heatmapCells,
                    roadSegments: streets,
                  ),
                  size: const Size(150, 118),
                ),
              ),
              if (onExpand != null)
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    icon: const Icon(Icons.open_in_full, size: 14, color: Colors.white70),
                    onPressed: onExpand,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ),
              const Positioned(
                left: 6,
                bottom: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Coverage', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        _LegendDot(Color(0xFF00E676)),
                        _LegendDot(Color(0xFFFF9800)),
                        _LegendDot(Color(0xFFE53935)),
                        _LegendDot(Color(0xFF616161)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      margin: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
