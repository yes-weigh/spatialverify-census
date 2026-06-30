import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/app_locale_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../data/hlb_map_pdf_exporter.dart';
import '../models/mission_models.dart';
import '../widgets/hlb_template_sheet_preview.dart';
import '../widgets/mission_line_feature_history.dart';
import 'mission_providers.dart';

class DraftHlbMapScreen extends ConsumerStatefulWidget {
  const DraftHlbMapScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<DraftHlbMapScreen> createState() => _DraftHlbMapScreenState();
}

class _DraftHlbMapScreenState extends ConsumerState<DraftHlbMapScreen> {
  final _enumNameCtrl = TextEditingController();
  final _enumDateCtrl = TextEditingController();
  final _supNameCtrl = TextEditingController();
  final _supDateCtrl = TextEditingController();
  var _footerLoaded = false;
  var _exporting = false;
  var _savingFooter = false;

  EbMissionQuery get _query => EbMissionQuery(ebId: widget.ebId, projectId: widget.projectId);

  @override
  void dispose() {
    _enumNameCtrl.dispose();
    _enumDateCtrl.dispose();
    _supNameCtrl.dispose();
    _supDateCtrl.dispose();
    super.dispose();
  }

  void _loadFooter(DraftHlbMap map) {
    if (_footerLoaded) return;
    final f = map.footerBlock;
    _enumNameCtrl.text = f.enumeratorName ?? '';
    _enumDateCtrl.text = f.enumeratorDate ?? _today();
    _supNameCtrl.text = f.supervisorName ?? '';
    _supDateCtrl.text = f.supervisorDate ?? '';
    _footerLoaded = true;
  }

  String _today() {
    final n = DateTime.now();
    return '${n.day.toString().padLeft(2, '0')}/${n.month.toString().padLeft(2, '0')}/${n.year}';
  }

  Future<void> _saveFooter() async {
    if (_savingFooter) return;
    setState(() => _savingFooter = true);
    try {
      final local = ref.read(missionLocalFirstProvider);
      await local.saveLayoutMapFooter(
        widget.ebId,
        enumeratorName: _enumNameCtrl.text.trim().isEmpty ? null : _enumNameCtrl.text.trim(),
        enumeratorDate: _enumDateCtrl.text.trim().isEmpty ? null : _enumDateCtrl.text.trim(),
        supervisorName: _supNameCtrl.text.trim().isEmpty ? null : _supNameCtrl.text.trim(),
        supervisorDate: _supDateCtrl.text.trim().isEmpty ? null : _supDateCtrl.text.trim(),
      );
      ref.invalidate(draftMapProvider(_query));
      if (!mounted) return;
      final s = ref.read(appStringsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.footerSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingFooter = false);
    }
  }

  Future<void> _exportPdf(DraftHlbMap map) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await _saveFooter();
      if (!mounted) return;
      final mapAsync = await ref.read(draftMapProvider(_query).future);
      final state = await ref.read(missionLocalFirstProvider).getRawState(widget.ebId);
      await shareHlbMapPdfFromState(
        map: mapAsync,
        layoutGeoref: state?.layoutGeoref,
        ebId: widget.ebId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapAsync = ref.watch(draftMapProvider(_query));
    final templateAsync = ref.watch(hlbExportTemplateProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draft HLB Map'),
        actions: [
          mapAsync.maybeWhen(
            data: (map) => IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              tooltip: 'Download HLB map PDF',
              onPressed: _exporting ? null : () => _exportPdf(map),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: mapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (map) {
          _loadFooter(map);
          return templateAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (layout) {
              final previewAspect = layout.pageSize.widthPt / layout.pageSize.heightPt;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AspectRatio(
                    aspectRatio: previewAspect,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: HlbTemplateSheetPreview(mapData: map, layout: layout),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    layout.hasTemplate
                        ? 'Original PDF layout (left panel + borders) with your field drawings'
                        : 'Re-import HLO PDF to show the official left panel and borders',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  const Text('Enumerator & supervisor (footer)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _enumNameCtrl,
                    decoration: const InputDecoration(labelText: 'Enumerator name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _enumDateCtrl,
                    decoration: const InputDecoration(labelText: 'Enumerator date', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _supNameCtrl,
                    decoration: const InputDecoration(labelText: 'Supervisor name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _supDateCtrl,
                    decoration: const InputDecoration(labelText: 'Supervisor date', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _savingFooter ? null : _saveFooter,
                    icon: _savingFooter
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_savingFooter ? 'Saving…' : 'Save footer on map'),
                  ),
                  const SizedBox(height: 16),
                  const Text('Serpentine order (NW → SE)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final e in map.serpentineOrder)
                        Chip(label: Text(e.label, style: const TextStyle(fontSize: 11))),
                    ],
                  ),
                  if (map.startPoint != null)
                    Text(
                      'Start: Bldg ${map.startPoint!.buildingNumber ?? '?'}  ·  End: Bldg ${map.endPoint?.buildingNumber ?? '?'}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  if (map.buildings.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        'Walk your HLB and confirm buildings — the layout map fills from GPS marks.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  const SizedBox(height: 16),
                  MissionLineFeatureHistoryPanel(
                    projectId: widget.projectId,
                    ebId: widget.ebId,
                    lines: map.lineFeatures,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back to mission map'),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
