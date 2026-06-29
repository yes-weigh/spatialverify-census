import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../data/mission_completion.dart';
import '../data/mission_intelligence_engine.dart';
import '../data/discovery_analytics.dart';
import '../models/mission_models.dart';
import 'mission_providers.dart';

/// Primary HLB screen — Discovery First, not navigation first.
class DiscoveryHubScreen extends ConsumerWidget {
  const DiscoveryHubScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  EbMissionQuery get _query => EbMissionQuery(ebId: ebId, projectId: projectId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(_query));
    final intelligenceAsync = ref.watch(missionIntelligenceProvider(_query));
    final completionAsync = ref.watch(missionCompletionProvider(_query));
    final analyticsAsync = ref.watch(hlbAnalyticsProvider(_query));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('HLB Discovery'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Discovery replay',
            onPressed: () => context.push('/mission/$projectId/eb/$ebId/replay'),
          ),
          IconButton(
            icon: const Icon(Icons.dashboard_outlined),
            tooltip: 'Discovery dashboard',
            onPressed: () => context.push('/mission/$projectId/eb/$ebId/dashboard'),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push('/mission/$projectId/eb/$ebId/gaps'),
          ),
        ],
      ),
      body: discoveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('HLB ${d.ebCode}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  d.hasOfficialBoundary
                      ? (d.officialBoundaryAreaLabel != null
                          ? 'Georeferenced boundary loaded — discover everything inside your assigned HLB.'
                          : 'Official boundary loaded — discover everything inside your assigned HLB.')
                      : 'Set up your HLB boundary to begin discovery.',
                  style: const TextStyle(color: AppTheme.textSecondary, height: 1.4),
                ),
                if (!d.hasOfficialBoundary) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/mission/$projectId/eb/$ebId/georef'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Import HLO PDF'),
                  ),
                ],
                if (d.hasOfficialBoundary) ...[
                  const SizedBox(height: 16),
                  _OfficialBoundaryCard(discovery: d),
                ],
                intelligenceAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (intel) {
                    if (intel == null || !intel.hasData) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: _MissionIntelligenceCard(intelligence: intel),
                    );
                  },
                ),
                completionAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (c) => d.hasOfficialBoundary
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: _MissionCompletionCard(completion: c),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 28),
                _MetricGrid(discovery: d),
                const SizedBox(height: 16),
                analyticsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (a) => a.streets.isNotEmpty
                      ? _StreetCompletionSection(streets: a.streets)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
                _GapSummaryCard(
                  summary: d.gapSummary,
                  onReview: () => context.push('/mission/$projectId/eb/$ebId/gaps'),
                ),
                const SizedBox(height: 24),
                _OpenMapButton(
                  onOpenMap: () => context.go('/mission/$projectId/eb/$ebId'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/mission/$projectId/eb/$ebId/draft-map'),
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Draft Map'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (d.buildingsDiscovered > 0)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => context.push('/mission/$projectId/eb/$ebId/listing'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00897B)),
                          child: const Text('House Listing'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MissionCompletionCard extends StatelessWidget {
  const _MissionCompletionCard({required this.completion});
  final MissionCompletionIndex completion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: completion.canSubmit ? const Color(0xFF00E676).withValues(alpha: 0.4) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Mission Completion ${completion.overallPercent}%',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              if (completion.canSubmit)
                const Text('Ready to submit', style: TextStyle(color: Color(0xFF00E676), fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          _CompletionRow('Coverage', completion.coveragePercent),
          _CompletionRow('Observation targets', completion.observationTargetsCompletedPercent),
          _CompletionRow('Roads walked', completion.roadsWalkedPercent),
          _CompletionRow('Boundary verified', completion.boundaryVerifiedPercent),
          if (completion.ignoredTargets > 0)
            Text('Ignored targets: ${completion.ignoredTargets}', style: const TextStyle(color: Colors.orange, fontSize: 12)),
          if (completion.openGaps > 0)
            Text('Open gaps: ${completion.openGaps}', style: const TextStyle(color: Colors.orange, fontSize: 12)),
        ],
      ),
    );
  }
}

class _CompletionRow extends StatelessWidget {
  const _CompletionRow(this.label, this.percent);
  final String label;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
          Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _MissionIntelligenceCard extends StatelessWidget {
  const _MissionIntelligenceCard({required this.intelligence});
  final MissionIntelligenceSummary intelligence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2233),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF42A5F5).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.psychology_outlined, color: Color(0xFF42A5F5), size: 20),
              SizedBox(width: 8),
              Text('Mission Intelligence', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF42A5F5))),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Predicted targets from your layout map — mark on the map', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _IntelChip('${intelligence.estimatedStructures} observation targets'),
              _IntelChip('${intelligence.roadSegments} roads'),
              _IntelChip('${intelligence.possibleLandmarks} landmarks'),
              if (intelligence.canalCrossings > 0) _IntelChip('${intelligence.canalCrossings} canal crossings'),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntelChip extends StatelessWidget {
  const _IntelChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF42A5F5).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _OfficialBoundaryCard extends StatelessWidget {
  const _OfficialBoundaryCard({required this.discovery});

  final DiscoveryStatus discovery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.verified_outlined, color: Color(0xFF00E676), size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text('Boundary Ready ✓', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF00E676))),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            discovery.boundarySource == 'layout_map'
                ? 'Source: Officer Satellite Map'
                : 'Source: Official GIS',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          if (discovery.officialBoundaryAreaLabel != null)
            Text('Area: ${discovery.officialBoundaryAreaLabel}', style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(
            discovery.startPointDistanceLabel != null
                ? 'NW corner: ${discovery.startPointDistanceLabel} away (optional)'
                : 'Mark buildings from anywhere on the map',
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.discovery});
  final DiscoveryStatus discovery;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _MetricTile(
              discovery.hasOfficialBoundary ? 'Visited Area' : 'Boundary',
              '${discovery.boundaryCoveragePercent}%',
              discovery.hasOfficialBoundary ? Icons.map_outlined : Icons.pentagon_outlined,
            )),
            const SizedBox(width: 10),
            Expanded(child: _MetricTile('Road coverage', '${discovery.roadCoveragePercent}%', Icons.alt_route)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _MetricTile('Buildings', '${discovery.buildingsDiscovered}', Icons.home_work_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _MetricTile('Landmarks', '${discovery.landmarksDiscovered}', Icons.place_outlined)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _MetricTile('Walking time', discovery.walkingTimeLabel, Icons.timer_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _MetricTile('Path walked', discovery.pathWalkedLabel, Icons.directions_walk)),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF42A5F5), size: 20),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _OpenMapButton extends StatelessWidget {
  const _OpenMapButton({required this.onOpenMap});

  final VoidCallback onOpenMap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 12,
      shadowColor: const Color(0xFF42A5F5).withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpenMap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.map_outlined, color: Colors.white, size: 28),
              SizedBox(width: 12),
              Text(
                'OPEN MAP',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StreetCompletionSection extends StatelessWidget {
  const _StreetCompletionSection({required this.streets});
  final List<StreetSegment> streets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Street Completion', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        const Text('Where you walked — not grid cells', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        ...streets.take(4).map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _StreetCard(street: s),
            )),
      ],
    );
  }
}

class _StreetCard extends StatelessWidget {
  const _StreetCard({required this.street});
  final StreetSegment street;

  @override
  Widget build(BuildContext context) {
    final pct = street.completionPercent;
    final color = pct >= 90
        ? const Color(0xFF00E676)
        : pct >= 60
            ? const Color(0xFFFF9800)
            : const Color(0xFFE53935);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(street.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  '${street.buildingsTotal} Buildings · ${street.buildingsConfirmed} Confirmed',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Text('$pct%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
        ],
      ),
    );
  }
}

class _GapSummaryCard extends StatelessWidget {
  const _GapSummaryCard({required this.summary, required this.onReview});
  final GapSummary summary;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: summary.highPriority > 0 ? const Color(0xFF2A1A1A) : const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: summary.highPriority > 0 ? Colors.orange.withValues(alpha: 0.35) : Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Coverage Assurance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            summary.open == 0
                ? 'No open gaps — coverage looks solid'
                : 'High: ${summary.highPriority} · Medium: ${summary.mediumPriority} · Low: ${summary.lowPriority}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          if (summary.open > 0) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onReview, child: const Text('Review Coverage Gaps')),
            ),
          ],
        ],
      ),
    );
  }
}
