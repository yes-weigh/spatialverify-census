import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/mission_local_first_service.dart';
import '../models/mission_models.dart';
import '../utils/mission_navigation.dart';
import '../widgets/bearing_arrow.dart';
import '../widgets/hlb_map_painter.dart';
import 'mission_providers.dart';

/// Map-highlighted coverage gaps with bearing navigation and resolution audit trail.
class CoverageGapsScreen extends ConsumerStatefulWidget {
  const CoverageGapsScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  CoverageGapsQuery get _gapsQuery => CoverageGapsQuery(ebId: ebId, projectId: projectId);

  @override
  ConsumerState<CoverageGapsScreen> createState() => _CoverageGapsScreenState();
}

class _CoverageGapsScreenState extends ConsumerState<CoverageGapsScreen> with MissionGpsTracking {
  String? _selectedGapId;
  bool _navigating = false;
  String _filter = 'open';

  MissionLocalFirstService get _local => ref.read(missionLocalFirstProvider);

  CoverageGapsQuery _queryWithPosition() => CoverageGapsQuery(
        ebId: widget.ebId,
        projectId: widget.projectId,
        latitude: position?.latitude,
        longitude: position?.longitude,
      );

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  Future<void> _initGps() async {
    await ensureLocationPermission();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: (pos) {
        if (mounted) {
          ref.invalidate(coverageGapsProvider(CoverageGapsQuery(
            ebId: widget.ebId,
            projectId: widget.projectId,
            latitude: pos.latitude,
            longitude: pos.longitude,
          )));
          setState(() {});
        }
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(coverageGapsProvider(_queryWithPosition()));
    ref.invalidate(draftMapProvider(widget._gapsQuery.mission));
    ref.invalidate(discoveryStatusProvider(widget._gapsQuery.mission));
  }

  List<CoverageGap> _filtered(List<CoverageGap> gaps) {
    switch (_filter) {
      case 'high':
        return gaps.where((g) => !g.isResolved && g.severity == 'high').toList();
      case 'medium':
        return gaps.where((g) => !g.isResolved && g.severity == 'medium').toList();
      case 'resolved':
        return gaps.where((g) => g.isResolved).toList();
      default:
        return gaps.where((g) => !g.isResolved).toList();
    }
  }

  CoverageGap? _selected(List<CoverageGap> gaps) {
    if (_selectedGapId == null) return null;
    try {
      return gaps.firstWhere((g) => g.id == _selectedGapId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _resolveGap(CoverageGap gap, String resolution, {String? notes}) async {
    await _local.resolveCoverageGap(
      widget.ebId,
      gapId: gap.id,
      resolution: resolution,
      gapType: gap.type,
      gapReason: gap.reason,
      notes: notes,
      latitude: gap.latitude,
      longitude: gap.longitude,
      resolvedLatitude: position?.latitude,
      resolvedLongitude: position?.longitude,
    );
    _navigating = false;
    _selectedGapId = null;
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gap resolved: ${_resolutionLabel(resolution)}')),
      );
    }
  }

  String _resolutionLabel(String r) {
    switch (r) {
      case 'building_found':
        return 'Building found';
      case 'no_building':
        return 'No building exists';
      case 'not_accessible':
        return 'Not accessible';
      default:
        return 'Investigated';
    }
  }

  void _showResolutionSheet(CoverageGap gap) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(gap.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(gap.description, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              if (gap.isNavigable && !_navigating)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedGapId = gap.id;
                      _navigating = true;
                    });
                  },
                  icon: const Icon(Icons.navigation_outlined),
                  label: const Text('Navigate'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resolveGap(gap, 'investigated');
                },
                child: const Text('Mark Investigated'),
              ),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resolveGap(gap, 'not_accessible');
                },
                child: const Text('Not Accessible'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.verified),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _resolveGap(gap, 'building_found');
                  if (mounted) context.go('/mission/${widget.projectId}/eb/${widget.ebId}');
                },
                child: const Text('Building Found — Add Building'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _resolveGap(gap, 'no_building');
                },
                child: const Text('No Building Exists'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gapsAsync = ref.watch(coverageGapsProvider(_queryWithPosition()));
    final mapAsync = ref.watch(draftMapProvider(widget._gapsQuery.mission));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coverage Gaps'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
        ],
      ),
      body: gapsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (data) {
          final gaps = _filtered(data.gaps);
          final selected = _selected(data.gaps);
          final bearing = selected != null
              ? MissionNavigation.bearingToLatLng(position, selected.latitude, selected.longitude)
              : null;
          final distance = selected != null
              ? MissionNavigation.distanceLabelToLatLng(position, selected.latitude, selected.longitude)
              : null;
          final arrived = selected != null
              ? MissionNavigation.isArrivedAtLatLng(position, selected.latitude, selected.longitude)
              : false;

          return Column(
            children: [
              if (_navigating && selected != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  child: Column(
                    children: [
                      Text(selected.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (distance != null)
                        Text('$distance away', style: const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      BearingArrow(
                        targetBearing: bearing,
                        distanceLabel: distance,
                        isArrived: arrived,
                        size: 100,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() => _navigating = false),
                              child: const Text('Stop'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _showResolutionSheet(selected),
                              child: const Text('Resolve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _SummaryChip(label: 'High', count: data.summary.highPriority, color: const Color(0xFFD32F2F)),
                    const SizedBox(width: 8),
                    _SummaryChip(label: 'Medium', count: data.summary.mediumPriority, color: const Color(0xFFF57C00)),
                    const SizedBox(width: 8),
                    _SummaryChip(label: 'Low', count: data.summary.lowPriority, color: AppTheme.textSecondary),
                    const Spacer(),
                    Text('${data.summary.resolved} resolved', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(label: 'Open', value: 'open', group: _filter, onSelect: (v) => setState(() => _filter = v)),
                      _FilterChip(label: 'High', value: 'high', group: _filter, onSelect: (v) => setState(() => _filter = v)),
                      _FilterChip(label: 'Medium', value: 'medium', group: _filter, onSelect: (v) => setState(() => _filter = v)),
                      _FilterChip(label: 'Resolved', value: 'resolved', group: _filter, onSelect: (v) => setState(() => _filter = v)),
                    ],
                  ),
                ),
              ),
              mapAsync.when(
                loading: () => const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
                error: (_, __) => const SizedBox.shrink(),
                data: (map) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CustomPaint(
                          painter: HlbMapPainter(
                            mapData: map,
                            gaps: data.gaps,
                            selectedGapId: _selectedGapId,
                            highlightGaps: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: gaps.isEmpty
                    ? const Center(
                        child: Text(
                          'No open coverage gaps — coverage looks solid.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: gaps.length,
                        itemBuilder: (context, index) {
                          final g = gaps[index];
                          final isSelected = g.id == _selectedGapId;
                          return Card(
                            color: isSelected ? AppTheme.primary.withValues(alpha: 0.08) : null,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: _SeverityIcon(severity: g.severity, resolved: g.isResolved),
                              title: Text(g.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Text(
                                [
                                  g.description,
                                  if (g.distanceLabel != null) g.distanceLabel!,
                                  if (g.isResolved) 'Resolved: ${_resolutionLabel(g.resolution!.status)}',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: g.isResolved
                                  ? const Icon(Icons.check_circle, color: AppTheme.verified, size: 20)
                                  : const Icon(Icons.chevron_right),
                              onTap: () {
                                setState(() => _selectedGapId = g.id);
                                if (!g.isResolved) _showResolutionSheet(g);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label: $count', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.value, required this.group, required this.onSelect});
  final String label;
  final String value;
  final String group;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = group == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelect(value),
      ),
    );
  }
}

class _SeverityIcon extends StatelessWidget {
  const _SeverityIcon({required this.severity, required this.resolved});
  final String severity;
  final bool resolved;

  @override
  Widget build(BuildContext context) {
    if (resolved) return const Icon(Icons.verified_outlined, color: AppTheme.verified);
    final color = severity == 'high'
        ? const Color(0xFFD32F2F)
        : severity == 'low'
            ? AppTheme.textSecondary
            : const Color(0xFFF57C00);
    return Icon(Icons.warning_amber_rounded, color: color, size: 22);
  }
}
