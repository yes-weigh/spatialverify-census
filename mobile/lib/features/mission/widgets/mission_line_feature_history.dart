import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../data/hlb_feature_painter.dart';
import '../data/hlb_official_catalog.dart';
import '../models/mission_models.dart';
import '../presentation/mission_providers.dart';

/// Saved road/canal/path lines on the draft house-listing layout map — view and delete.
class MissionLineFeatureHistoryPanel extends ConsumerWidget {
  const MissionLineFeatureHistoryPanel({
    required this.projectId,
    required this.ebId,
    required this.lines,
    this.onChanged,
    super.key,
  });

  final String projectId;
  final String ebId;
  final List<DraftMapLineFeature> lines;
  final VoidCallback? onChanged;

  EbMissionQuery get _query => EbMissionQuery(ebId: ebId, projectId: projectId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'No roads, canals, or paths drawn yet.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Line drawings (${lines.length})',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        const Text(
          'Each traced line on the layout map. Delete if drawn incorrectly.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        for (final line in lines)
          _LineHistoryTile(
            line: line,
            onDelete: () => _confirmDelete(context, ref, line),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, DraftMapLineFeature line) async {
    final label = lineTitle(line);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete line?'),
        content: Text('Remove "$label" from the layout map?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final local = ref.read(missionLocalFirstProvider);
    await local.deleteRoadSegment(ebId, line.id);
    ref.invalidate(draftMapProvider(_query));
    ref.invalidate(discoveryStatusProvider(_query));
    onChanged?.call();
  }

  static String lineTitle(DraftMapLineFeature line) {
    final type = HlbOfficialCatalog.lineFeatureLabel(line.segmentType);
    if (line.name != null && line.name!.trim().isNotEmpty) {
      return '${line.name} ($type)';
    }
    return type;
  }
}

class _LineHistoryTile extends StatelessWidget {
  const _LineHistoryTile({required this.line, required this.onDelete});

  final DraftMapLineFeature line;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final type = HlbOfficialCatalog.normalizeLineType(line.segmentType);
    final color = HlbFeaturePainter.lineFeatureColor(type);
    final title = MissionLineFeatureHistoryPanel.lineTitle(line);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1E1E2A),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 4,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          '${line.points.length} points',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
          tooltip: 'Delete line',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
