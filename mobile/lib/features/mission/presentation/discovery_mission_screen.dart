import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/mission_local_first_service.dart';
import '../models/mission_models.dart';
import '../widgets/bearing_arrow.dart';
import 'mission_landing_screen.dart';
import 'mission_providers.dart';

/// HLB ground-truth mapping — Day 1–3 draft map creation while walking.
class DiscoveryMissionScreen extends ConsumerStatefulWidget {
  const DiscoveryMissionScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  EbMissionQuery get _query => EbMissionQuery(ebId: ebId, projectId: projectId);

  @override
  ConsumerState<DiscoveryMissionScreen> createState() => _DiscoveryMissionScreenState();
}

class _DiscoveryMissionScreenState extends ConsumerState<DiscoveryMissionScreen> with MissionGpsTracking {
  MissionLocalFirstService get _local => ref.read(missionLocalFirstProvider);

  @override
  void initState() {
    super.initState();
    _initGps();
  }

  Future<void> _initGps() async {
    await ensureLocationPermission();
    startMissionGps(
      ebId: widget.ebId,
      onPosition: (_) => setState(() {}),
      onBreadcrumb: (pos) {
        _local.addBreadcrumb(widget.ebId, pos.latitude, pos.longitude, accuracy: pos.accuracy);
        ref.invalidate(discoveryStatusProvider(widget._query));
      },
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(discoveryStatusProvider(widget._query));
  }

  @override
  Widget build(BuildContext context) {
    final discoveryAsync = ref.watch(discoveryStatusProvider(widget._query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('HLB Mapping'),
        actions: [
          IconButton(icon: const Icon(Icons.map_outlined), tooltip: 'Draft map', onPressed: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/draft-map')),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit draft map',
            onPressed: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/edit'),
          ),
        ],
      ),
      body: discoveryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (d) => RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('HLB Discovery', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppTheme.textSecondary)),
              Text('EB ${d.ebCode}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Next building: ${d.suggestedNextLabel} (NW→SE serpentine)',
                style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                d.phase == 'mapping' ? 'Prove no building was missed' : 'Draft complete — house listing',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 20),
              _StatGrid(discovery: d),
              const SizedBox(height: 16),
              _GapSummaryCard(
                summary: d.gapSummary,
                onReviewGaps: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/gaps'),
              ),
              if (d.gapSummary.open > 0) ...[
                const SizedBox(height: 12),
                for (final g in d.coverageGaps.take(3))
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        _gapIcon(g.type),
                        color: g.severity == 'high' ? const Color(0xFFD32F2F) : const Color(0xFFF57C00),
                        size: 22,
                      ),
                      title: Text(g.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        [g.description, if (g.distanceLabel != null) g.distanceLabel!].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/gaps'),
                    ),
                  ),
              ],
              if (d.zeroExclusionWarnings.isNotEmpty) ...[
                const Text('Zero Exclusion Alerts', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.pending)),
                const SizedBox(height: 8),
                for (final w in d.zeroExclusionWarnings)
                  Card(
                    color: (w.severity == 'high' ? AppTheme.pending : Colors.orange).withValues(alpha: 0.1),
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded, color: w.severity == 'high' ? AppTheme.pending : Colors.orange),
                      title: Text(w.description, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
              ],
              if (d.numberingIssues.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Numbering (NW→SE)', style: TextStyle(fontWeight: FontWeight.w600)),
                for (final n in d.numberingIssues)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.numbers, size: 20),
                    title: Text('Building ${n.buildingNumber} → expected ${n.expectedLabel}', style: const TextStyle(fontSize: 12)),
                  ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Walk your HLB boundary and confirm every building you see. '
                'This draft map is corrected during house listing — not final on Day 1.',
                style: TextStyle(color: AppTheme.textSecondary, height: 1.4, fontSize: 13),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.push('/mission/${widget.projectId}/eb/${widget.ebId}/draft-map'),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Preview Draft HLB Map'),
              ),
              if (d.buildingsDiscovered > 0 && d.phase == 'mapping') ...[
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _finalizeDraft(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: const Color(0xFF00897B),
                  ),
                  child: Text('Start House Listing (${d.buildingsDiscovered} buildings)'),
                ),
              ],
              if (d.phase == 'listing') ...[
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => context.go('/mission/${widget.projectId}/eb/${widget.ebId}'),
                  child: const Text('Continue House Listing'),
                ),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'landmark',
            onPressed: position == null ? null : () => _addLandmark(context),
            icon: const Icon(Icons.place_outlined),
            label: const Text('Landmark'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'boundary',
            onPressed: position == null ? null : () => _addBoundaryPoint(context),
            icon: const Icon(Icons.pentagon_outlined),
            label: const Text('Boundary'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'building',
            onPressed: position == null ? null : () => _confirmBuilding(context),
            backgroundColor: AppTheme.primary,
            icon: const Icon(Icons.add_home_work_outlined),
            label: const Text('Add Building'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmBuilding(BuildContext context) async {
    final d = ref.read(discoveryStatusProvider(widget._query)).valueOrNull;
    if (position == null || d == null) return;

    var type = 'pucca_residential';
    final countCtrl = TextEditingController(text: '1');
    var suggestedNum = d.suggestedNextBuildingNumber;
    var suggestedLabel = d.suggestedNextLabel;

    try {
      suggestedNum = await _local.suggestBuildingNumber(
            widget.ebId,
            position!.latitude,
            position!.longitude,
          );
      suggestedLabel = 'CN-${suggestedNum.toString().padLeft(3, '0')}';
    } catch (_) {}

    final numCtrl = TextEditingController(text: '$suggestedNum');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Building'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ground truth: you saw this building. GPS and number will be saved.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: numCtrl,
              decoration: InputDecoration(labelText: 'Building number ($suggestedLabel suggested)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: countCtrl,
              decoration: const InputDecoration(labelText: 'Census houses (if known)'),
              keyboardType: TextInputType.number,
            ),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'pucca_residential', child: Text('Residential □ (pucca)')),
                DropdownMenuItem(value: 'non_residential_pucca', child: Text('Non-residential ▨')),
                DropdownMenuItem(value: 'kutcha_residential', child: Text('Residential △ (kutcha)')),
                DropdownMenuItem(value: 'kutcha_non_residential', child: Text('Non-residential ▲')),
              ],
              onChanged: (v) => type = v ?? type,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );

    if (ok != true) return;

    await _local.discoverBuilding(
      widget.ebId,
      latitude: position!.latitude,
      longitude: position!.longitude,
      buildingType: type,
      censusHouseCount: int.tryParse(countCtrl.text) ?? 1,
      buildingNumber: int.tryParse(numCtrl.text),
    );
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Building ${numCtrl.text} recorded')),
      );
    }
  }

  IconData _gapIcon(String type) {
    switch (type) {
      case 'unwalked_road':
        return Icons.alt_route;
      case 'boundary_gap':
        return Icons.pentagon_outlined;
      case 'empty_cluster':
        return Icons.location_searching;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> _addBoundaryPoint(BuildContext context) async {
    if (position == null) return;
    await _local.addBoundaryVertex(widget.ebId, position!.latitude, position!.longitude);
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boundary point saved')),
      );
    }
  }

  Future<void> _addLandmark(BuildContext context) async {
    if (position == null) return;
    final nameCtrl = TextEditingController();
    var type = 'other';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Landmark'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'school', child: Text('School')),
                DropdownMenuItem(value: 'temple', child: Text('Temple')),
                DropdownMenuItem(value: 'mosque', child: Text('Mosque')),
                DropdownMenuItem(value: 'hospital', child: Text('Hospital')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => type = v ?? type,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.isEmpty) return;

    await _local.discoverLandmark(
      widget.ebId,
      name: nameCtrl.text,
      landmarkType: type,
      latitude: position!.latitude,
      longitude: position!.longitude,
    );
    await _refresh();
  }

  Future<void> _finalizeDraft(BuildContext context) async {
    final validation = await _local.validateDiscovery(widget.ebId);
    final highGaps = validation.gapSummary?.highPriority ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start House Listing?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your draft HLB map becomes your working map. '
              'You can still add or correct buildings during listing.',
            ),
            if (highGaps > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$highGaps high-priority coverage gap(s) remain — investigate before listing.',
                style: TextStyle(color: AppTheme.pending, fontSize: 13),
              ),
            ],
            if (validation.ignoredSuggestionsCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${validation.ignoredSuggestionsCount} possible structure(s) ignored — review before finalizing.',
                style: TextStyle(color: AppTheme.pending, fontSize: 13),
              ),
            ],
            if (validation.canFinalize)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Coverage checks passed.', style: TextStyle(color: AppTheme.verified, fontSize: 13)),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Mapping')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start Listing')),
        ],
      ),
    );
    if (ok != true) return;

    await _local.finalizeDraftMap(widget.ebId);
    ref.invalidate(activeMissionProvider);
    if (mounted) {
      context.go('/mission/${widget.projectId}/eb/${widget.ebId}');
    }
  }
}

class _GapSummaryCard extends StatelessWidget {
  const _GapSummaryCard({required this.summary, required this.onReviewGaps});

  final GapSummary summary;
  final VoidCallback onReviewGaps;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: summary.highPriority > 0 ? AppTheme.pending.withValues(alpha: 0.08) : null,
      child: InkWell(
        onTap: onReviewGaps,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Coverage Assurance', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                summary.open == 0
                    ? 'No open gaps — coverage looks solid'
                    : 'High priority: ${summary.highPriority}  ·  Medium: ${summary.mediumPriority}  ·  Low: ${summary.lowPriority}',
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              if (summary.resolved > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${summary.resolved} gap(s) investigated and resolved',
                    style: const TextStyle(color: AppTheme.verified, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onReviewGaps,
                  icon: const Icon(Icons.explore_outlined),
                  label: Text(summary.open > 0 ? 'Review & Navigate Gaps' : 'View Coverage Map'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.discovery});
  final DiscoveryStatus discovery;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Boundary', value: '${discovery.boundaryCoveragePercent}%')),
            const SizedBox(width: 8),
            Expanded(child: _StatTile(label: 'Road coverage', value: '${discovery.roadCoveragePercent}%')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Buildings', value: '${discovery.buildingsDiscovered}')),
            const SizedBox(width: 8),
            Expanded(child: _StatTile(label: 'Landmarks', value: '${discovery.landmarksDiscovered}')),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _StatTile(label: 'Walking time', value: discovery.walkingTimeLabel)),
            const SizedBox(width: 8),
            Expanded(child: _StatTile(label: 'Path walked', value: discovery.pathWalkedLabel)),
          ],
        ),
        if (discovery.boundaryVertices > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              discovery.boundaryClosed
                  ? 'HLB boundary closed ✓'
                  : '${discovery.boundaryVertices} boundary points — walk back to close',
              style: TextStyle(
                fontSize: 12,
                color: discovery.boundaryClosed ? AppTheme.verified : AppTheme.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.glassDecoration(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
