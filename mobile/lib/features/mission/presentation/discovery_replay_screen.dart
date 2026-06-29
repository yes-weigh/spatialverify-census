import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/discovery_analytics.dart';
import '../models/mission_models.dart';
import 'mission_providers.dart';

/// End-of-day discovery replay — animated walk path + confirmation timeline.
class DiscoveryReplayScreen extends ConsumerStatefulWidget {
  const DiscoveryReplayScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<DiscoveryReplayScreen> createState() => _DiscoveryReplayScreenState();
}

class _DiscoveryReplayScreenState extends ConsumerState<DiscoveryReplayScreen> with SingleTickerProviderStateMixin {
  late AnimationController _playCtrl;
  int _highlightIdx = 0;

  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void initState() {
    super.initState();
    _playCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..addListener(_onTick);
  }

  void _onTick() {
    final analytics = ref.read(hlbAnalyticsProvider(_query)).asData?.value;
    if (analytics == null || analytics.replay.isEmpty) return;
    final idx = (_playCtrl.value * analytics.replay.length).floor().clamp(0, analytics.replay.length - 1);
    if (idx != _highlightIdx) setState(() => _highlightIdx = idx);
  }

  @override
  void dispose() {
    _playCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(hlbAnalyticsProvider(_query));
    final mapAsync = ref.watch(draftMapProvider(_query));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        title: const Text('Discovery Replay'),
        backgroundColor: Colors.transparent,
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (analytics) {
          final events = analytics.replay;
          if (events.isEmpty) {
            return const Center(
              child: Text('No discovery events yet — start a walk first', style: TextStyle(color: AppTheme.textSecondary)),
            );
          }
          return Column(
            children: [
              Expanded(
                flex: 2,
                child: mapAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (map) => _ReplayMap(
                    mapData: map,
                    events: events,
                    progress: _playCtrl.value,
                    highlightIdx: _highlightIdx,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(_playCtrl.isAnimating ? Icons.pause : Icons.play_arrow),
                          onPressed: () {
                            if (_playCtrl.isAnimating) {
                              _playCtrl.stop();
                            } else if (_playCtrl.value >= 1) {
                              _playCtrl.forward(from: 0);
                            } else {
                              _playCtrl.forward();
                            }
                          },
                        ),
                        Expanded(
                          child: Slider(
                            value: _playCtrl.value,
                            onChanged: (v) {
                              _playCtrl.value = v;
                              _onTick();
                            },
                          ),
                        ),
                        Text('${events.length} events', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                      ],
                    ),
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (_, i) {
                          final e = events[i];
                          final active = i == _highlightIdx;
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: active ? const Color(0xFF42A5F5) : Colors.white12,
                              child: Icon(_iconFor(e.type), size: 14, color: Colors.white),
                            ),
                            title: Text(
                              e.label,
                              style: TextStyle(
                                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                                color: active ? Colors.white : Colors.white70,
                              ),
                            ),
                            subtitle: Text(
                              DateFormat.Hm().format(e.time),
                              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'start':
        return Icons.directions_walk;
      case 'landmark':
        return Icons.place;
      default:
        return Icons.home_work_outlined;
    }
  }
}

class _ReplayMap extends StatelessWidget {
  const _ReplayMap({
    required this.mapData,
    required this.events,
    required this.progress,
    required this.highlightIdx,
  });

  final DraftHlbMap mapData;
  final List<DiscoveryReplayEvent> events;
  final double progress;
  final int highlightIdx;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: _ReplayPainter(mapData: mapData, events: events, progress: progress, highlightIdx: highlightIdx),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
        ),
      ),
    );
  }
}

class _ReplayPainter extends CustomPainter {
  _ReplayPainter({
    required this.mapData,
    required this.events,
    required this.progress,
    required this.highlightIdx,
  });

  final DraftHlbMap mapData;
  final List<DiscoveryReplayEvent> events;
  final double progress;
  final int highlightIdx;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 16.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;

    if (mapData.walkPath.length >= 2) {
      final path = Path();
      for (var i = 0; i < mapData.walkPath.length; i++) {
        final p = mapData.walkPath[i];
        final x = pad + p.x * w;
        final y = pad + p.y * h;
        if (i == 0) path.moveTo(x, y);
        else path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFFFD740).withValues(alpha: 0.6)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );

      final cutIdx = (mapData.walkPath.length * progress).floor().clamp(1, mapData.walkPath.length);
      final animPath = Path();
      for (var i = 0; i < cutIdx; i++) {
        final p = mapData.walkPath[i];
        final x = pad + p.x * w;
        final y = pad + p.y * h;
        if (i == 0) animPath.moveTo(x, y);
        else animPath.lineTo(x, y);
      }
      canvas.drawPath(
        animPath,
        Paint()
          ..color = const Color(0xFF42A5F5)
          ..strokeWidth = 4
          ..style = PaintingStyle.stroke,
      );
    }

    for (final b in mapData.buildings) {
      final p = Offset(pad + b.mapX * w, pad + b.mapY * h);
      final isActive = highlightIdx < events.length && events[highlightIdx].label == b.label;
      canvas.drawRect(
        Rect.fromCenter(center: p, width: isActive ? 10 : 6, height: isActive ? 10 : 6),
        Paint()..color = isActive ? const Color(0xFF00E676) : const Color(0xFF42A5F5),
      );
    }

    for (final lm in mapData.landmarks) {
      final p = Offset(pad + lm.mapX * w, pad + lm.mapY * h);
      canvas.drawCircle(p, 4, Paint()..color = const Color(0xFFCE93D8));
    }
  }

  @override
  bool shouldRepaint(covariant _ReplayPainter old) =>
      old.progress != progress || old.highlightIdx != highlightIdx;
}
