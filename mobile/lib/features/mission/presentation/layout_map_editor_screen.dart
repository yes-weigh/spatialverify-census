import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../models/mission_models.dart';
import '../data/mission_service.dart';
import 'eb_list_screen.dart';

class LayoutMapEditorScreen extends ConsumerStatefulWidget {
  const LayoutMapEditorScreen({required this.projectId, required this.ebId, super.key});

  final String projectId;
  final String ebId;

  @override
  ConsumerState<LayoutMapEditorScreen> createState() => _LayoutMapEditorScreenState();
}

class _LayoutMapEditorScreenState extends ConsumerState<LayoutMapEditorScreen> {
  EditorMode _mode = EditorMode.boundary;
  List<MapPoint> _boundary = [];
  List<MissionBuilding> _buildings = [];
  List<MissionLandmark> _landmarks = [];
  List<String> _routeIds = [];
  String? _layoutImageUrl;
  bool _loading = true;
  bool _saving = false;
  int _nextBuildingNumber = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await ref.read(missionApiProvider).getPlan(widget.ebId);
    setState(() {
      _boundary = plan.boundaryMap;
      _buildings = plan.buildings;
      _landmarks = plan.landmarks;
      _layoutImageUrl = plan.layoutImageUrl;
      _routeIds = plan.routeBuildingIds.isNotEmpty
          ? plan.routeBuildingIds
          : (List<MissionBuilding>.from(plan.buildings)
            ..sort((a, b) => (a.routeSequence ?? a.buildingNumber).compareTo(b.routeSequence ?? b.buildingNumber)))
              .map((b) => b.id)
              .toList();
      _nextBuildingNumber = _buildings.isEmpty
          ? 1
          : _buildings.map((b) => b.buildingNumber).reduce((a, b) => a > b ? a : b) + 1;
      _loading = false;
    });
  }

  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final url = await ref.read(missionApiProvider).uploadLayout(widget.ebId, file.path);
    setState(() => _layoutImageUrl = url);
  }

  void _onTapMap(Offset local, Size size) {
    final x = (local.dx / size.width).clamp(0.0, 1.0);
    final y = (local.dy / size.height).clamp(0.0, 1.0);

    if (_mode == EditorMode.boundary) {
      setState(() => _boundary.add(MapPoint(x, y)));
    } else if (_mode == EditorMode.building) {
      _addBuilding(x, y);
    } else if (_mode == EditorMode.landmark) {
      _addLandmark(x, y);
    }
  }

  Future<void> _addBuilding(double x, double y) async {
    final numCtrl = TextEditingController(text: '$_nextBuildingNumber');
    final countCtrl = TextEditingController(text: '1');
    var type = 'pucca_residential';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Building'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: numCtrl, decoration: const InputDecoration(labelText: 'Building Number'), keyboardType: TextInputType.number),
            TextField(controller: countCtrl, decoration: const InputDecoration(labelText: 'Census House Count'), keyboardType: TextInputType.number),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'pucca_residential', child: Text('Residential Pucca □')),
                DropdownMenuItem(value: 'non_residential_pucca', child: Text('Non-Residential Pucca ▨')),
                DropdownMenuItem(value: 'kutcha_residential', child: Text('Residential Kutcha △')),
                DropdownMenuItem(value: 'kutcha_non_residential', child: Text('Non-Residential Kutcha ▲')),
              ],
              onChanged: (v) => type = v ?? type,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );

    if (ok != true) return;
    final num = int.tryParse(numCtrl.text) ?? _nextBuildingNumber;
    final count = int.tryParse(countCtrl.text) ?? 1;

    setState(() {
      _buildings.add(MissionBuilding(
        id: 'local-$num',
        ebId: widget.ebId,
        buildingNumber: num,
        censusHouseCount: count,
        buildingType: type,
        mapX: x,
        mapY: y,
        status: 'not_visited',
        routeSequence: _buildings.length + 1,
      ));
      _nextBuildingNumber = num + 1;
    });
  }

  Future<void> _addLandmark(double x, double y) async {
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
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (v) => type = v ?? type,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.isEmpty) return;
    setState(() => _landmarks.add(MissionLandmark(name: nameCtrl.text, landmarkType: type, mapX: x, mapY: y)));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final routeOrder = _routeIds.isNotEmpty ? _routeIds : _buildings.map((b) => b.id).toList();
      final seqById = <String, int>{for (var i = 0; i < routeOrder.length; i++) routeOrder[i]: i + 1};
      final buildingsWithRoute = _buildings
          .map((b) => MissionBuilding(
                id: b.id,
                ebId: b.ebId,
                buildingNumber: b.buildingNumber,
                censusHouseCount: b.censusHouseCount,
                buildingType: b.buildingType,
                mapX: b.mapX,
                mapY: b.mapY,
                status: b.status,
                notes: b.notes,
                routeSequence: seqById[b.id] ?? b.routeSequence,
              ))
          .toList();

      final draft = MissionPlanDraft(
        boundaryMap: _boundary,
        buildings: buildingsWithRoute,
        landmarks: _landmarks,
      );
      await ref.read(missionApiProvider).savePlan(widget.ebId, draft);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mission plan saved')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startMission() async {
    await _save();
    await ref.read(missionApiProvider).startMission(widget.ebId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mission started — go walk your EB')));
      context.go('/mission/${widget.projectId}/eb/${widget.ebId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Layout Map Setup'),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else ...[
            IconButton(icon: const Icon(Icons.upload_file), tooltip: 'Upload layout map', onPressed: _uploadImage),
            IconButton(icon: const Icon(Icons.save), tooltip: 'Save', onPressed: _save),
            IconButton(icon: const Icon(Icons.play_arrow), tooltip: 'Start mission', onPressed: _startMission),
          ],
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _modeChip('Boundary', EditorMode.boundary),
                _modeChip('Building', EditorMode.building),
                _modeChip('Landmark', EditorMode.landmark),
                _modeChip('Route', EditorMode.route),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_layoutImageUrl != null)
                        CachedNetworkImage(
                          imageUrl: _layoutImageUrl!,
                          fit: BoxFit.contain,
                        )
                      else
                        const Center(
                          child: Text(
                            'Upload Layout Map image',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      GestureDetector(
                        onTapUp: (d) {
                          if (_mode != EditorMode.route) _onTapMap(d.localPosition, size);
                        },
                        child: CustomPaint(
                          size: size,
                          painter: _LayoutPainter(
                            boundary: _boundary,
                            buildings: _buildings,
                            landmarks: _landmarks,
                            routeIds: _routeIds,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          if (_mode == EditorMode.boundary)
            TextButton(onPressed: () => setState(() => _boundary.clear()), child: const Text('Clear boundary')),
          if (_mode == EditorMode.route)
            SizedBox(
              height: 120,
              child: ReorderableListView(
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex--;
                    final id = _routeIds.removeAt(oldIndex);
                    _routeIds.insert(newIndex, id);
                  });
                },
                children: [
                  for (final id in _routeIds)
                    ListTile(
                      key: ValueKey(id),
                      title: Text(
                        _buildings
                            .where((b) => b.id == id)
                            .map((b) => b.label)
                            .firstOrNull ?? 'Building',
                      ),
                      leading: const Icon(Icons.drag_handle),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, EditorMode mode) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _mode == mode,
        onSelected: (_) {
          setState(() {
            _mode = mode;
            if (mode == EditorMode.route && _routeIds.isEmpty) {
              _routeIds = _buildings.map((b) => b.id).toList();
            }
          });
        },
      ),
    );
  }
}

class _LayoutPainter extends CustomPainter {
  _LayoutPainter({
    required this.boundary,
    required this.buildings,
    required this.landmarks,
    required this.routeIds,
  });

  final List<MapPoint> boundary;
  final List<MissionBuilding> buildings;
  final List<MissionLandmark> landmarks;
  final List<String> routeIds;

  @override
  void paint(Canvas canvas, Size size) {
    if (boundary.length >= 2) {
      final path = Path();
      for (var i = 0; i < boundary.length; i++) {
        final p = Offset(boundary[i].x * size.width, boundary[i].y * size.height);
        if (i == 0) path.moveTo(p.dx, p.dy);
        else path.lineTo(p.dx, p.dy);
      }
      if (boundary.length >= 3) path.close();
      canvas.drawPath(path, Paint()..color = Colors.blue.withValues(alpha: 0.2)..style = PaintingStyle.fill);
      canvas.drawPath(path, Paint()..color = Colors.blue..strokeWidth = 2..style = PaintingStyle.stroke);
    }

    for (final b in buildings) {
      final p = Offset(b.mapX * size.width, b.mapY * size.height);
      canvas.drawRect(Rect.fromCenter(center: p, width: 14, height: 14), Paint()..color = missionStatusColor(b.status));
      final tp = TextPainter(
        text: TextSpan(text: b.label, style: const TextStyle(color: Colors.white, fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p + const Offset(-8, -20));
    }

    for (final lm in landmarks) {
      final p = Offset(lm.mapX * size.width, lm.mapY * size.height);
      canvas.drawCircle(p, 8, Paint()..color = Colors.orange);
    }

    // North arrow top-right
    final northBase = Offset(size.width - 30, 30);
    canvas.drawLine(northBase, northBase + const Offset(0, -20), Paint()..color = Colors.black..strokeWidth = 2);

    if (routeIds.length >= 2) {
      final byId = {for (final b in buildings) b.id: b};
      for (var i = 0; i < routeIds.length - 1; i++) {
        final a = byId[routeIds[i]];
        final c = byId[routeIds[i + 1]];
        if (a == null || c == null) continue;
        canvas.drawLine(
          Offset(a.mapX * size.width, a.mapY * size.height),
          Offset(c.mapX * size.width, c.mapY * size.height),
          Paint()..color = Colors.green..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutPainter old) => true;
}
