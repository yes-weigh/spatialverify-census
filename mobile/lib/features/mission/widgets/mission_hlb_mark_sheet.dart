import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/hlb_census_symbols.dart';
import '../data/hlb_official_catalog.dart';

typedef HlbBuildingMarkResult = ({
  String buildingType,
  int buildingNumber,
  int censusHouseCount,
});

typedef HlbLandmarkMarkResult = ({
  String name,
  String landmarkType,
});

/// Manual HLB marking sheet — official census symbols from any map location.
class MissionHlbMarkSheet {
  MissionHlbMarkSheet._();

  static Future<HlbBuildingMarkResult?> showBuilding(
    BuildContext context, {
    required int suggestedNumber,
    String? locationHint,
  }) {
    return showModalBottomSheet<HlbBuildingMarkResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BuildingMarkSheet(
        suggestedNumber: suggestedNumber,
        locationHint: locationHint,
      ),
    );
  }

  static Future<HlbLandmarkMarkResult?> showLandmark(
    BuildContext context, {
    String? locationHint,
    String? initialType,
  }) {
    return showModalBottomSheet<HlbLandmarkMarkResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _LandmarkMarkSheet(locationHint: locationHint, initialType: initialType),
    );
  }

  /// Layout-map feature (road, school, open space, etc.) per §4.4.3.
  static Future<HlbLandmarkMarkResult?> showMapFeature(
    BuildContext context, {
    String? locationHint,
  }) =>
      showLandmark(context, locationHint: locationHint);
}

class _BuildingMarkSheet extends StatefulWidget {
  const _BuildingMarkSheet({required this.suggestedNumber, this.locationHint});

  final int suggestedNumber;
  final String? locationHint;

  @override
  State<_BuildingMarkSheet> createState() => _BuildingMarkSheetState();
}

class _BuildingMarkSheetState extends State<_BuildingMarkSheet> {
  var _buildingType = 'pucca_residential';
  late final _numCtrl = TextEditingController(text: '${widget.suggestedNumber}');
  var _houseCount = 1;

  @override
  void dispose() {
    _numCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Add building', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          Text(
            widget.locationHint ?? 'Mark at your current location or long-press the map',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          const Text('Census symbol', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in HlbCensusSymbols.buildingTypes.entries)
                _TypeChip(entry.value, entry.key, _buildingType, (v) => setState(() => _buildingType = v)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _numCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Building number',
                    labelStyle: const TextStyle(color: Colors.white54),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              _Stepper(
                label: 'Houses',
                value: _houseCount,
                onChanged: (v) => setState(() => _houseCount = v),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(
                context,
                (
                  buildingType: _buildingType,
                  buildingNumber: int.tryParse(_numCtrl.text) ?? widget.suggestedNumber,
                  censusHouseCount: _houseCount,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            child: const Text('SAVE BUILDING', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
        ],
      ),
    );
  }
}

class _LandmarkMarkSheet extends StatefulWidget {
  const _LandmarkMarkSheet({this.locationHint, this.initialType});

  final String? locationHint;
  final String? initialType;

  @override
  State<_LandmarkMarkSheet> createState() => _LandmarkMarkSheetState();
}

class _LandmarkMarkSheetState extends State<_LandmarkMarkSheet> {
  final _nameCtrl = TextEditingController();
  late var _landmarkType = HlbOfficialCatalog.normalizeLandmarkType(widget.initialType ?? 'road');

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Add map feature', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text(
                    widget.locationHint ?? 'Roads, places, open land — per layout map instructions',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Label on map (e.g. Main Rd, Temple, Vacant plot)',
                      labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                children: [
                  for (final category in HlbCatalogCategory.values)
                    if (category != HlbCatalogCategory.buildings) ...[
                      Text(
                        HlbOfficialCatalog.categoryLabels[category]!,
                        style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final entry in HlbOfficialCatalog.landmarksInCategory(category))
                            _TypeChip(
                              entry.glyph != null ? '${entry.glyph} ${entry.label}' : entry.label,
                              entry.id,
                              _landmarkType,
                              (v) => setState(() => _landmarkType = v),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: ElevatedButton(
                onPressed: () {
                  final name = _nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(context, (name: name, landmarkType: _landmarkType));
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.black,
                ),
                child: const Text('SAVE ON HLB MAP', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.label, this.value, this.selected, this.onSelect);
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isSelected = selected == value;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? Colors.black : Colors.white)),
      selected: isSelected,
      onSelected: (_) => onSelect(value),
      selectedColor: const Color(0xFF42A5F5),
      backgroundColor: const Color(0xFF2A2A3E),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            Text('$value', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: Colors.white70),
              onPressed: () => onChanged(value + 1),
            ),
          ],
        ),
      ],
    );
  }
}
