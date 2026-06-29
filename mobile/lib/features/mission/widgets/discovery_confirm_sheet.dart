import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/hlb_official_catalog.dart';
import '../models/discovery_models.dart';

typedef DiscoveryConfirmCallback = void Function({
  required String buildingType,
  required int buildingNumber,
  required int censusHouseCount,
  String? featureLabel,
});

class DiscoveryConfirmSheet extends StatefulWidget {
  const DiscoveryConfirmSheet({
    required this.candidate,
    required this.suggestedNumber,
    required this.suggestedLabel,
    required this.onConfirm,
    required this.onReject,
    super.key,
  });

  final DiscoveryCandidate candidate;
  final int suggestedNumber;
  final String suggestedLabel;
  final DiscoveryConfirmCallback onConfirm;
  final VoidCallback onReject;

  static Future<void> show(
    BuildContext context, {
    required DiscoveryCandidate candidate,
    required int suggestedNumber,
    required String suggestedLabel,
    required DiscoveryConfirmCallback onConfirm,
    required VoidCallback onReject,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DiscoveryConfirmSheet(
        candidate: candidate,
        suggestedNumber: suggestedNumber,
        suggestedLabel: suggestedLabel,
        onConfirm: onConfirm,
        onReject: onReject,
      ),
    );
  }

  @override
  State<DiscoveryConfirmSheet> createState() => _DiscoveryConfirmSheetState();
}

class _DiscoveryConfirmSheetState extends State<DiscoveryConfirmSheet> {
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
    final c = widget.candidate;

    if (c.type == DiscoveryObjectType.landmark) {
      return _LandmarkSheet(candidate: c, onConfirm: widget.onConfirm, onReject: widget.onReject);
    }

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
          Text(c.typeLabel, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          const Text(
            'Should I add this?',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          const Text('Type', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TypeChip('□ Pucca Residential', 'pucca_residential', _buildingType, (v) => setState(() => _buildingType = v)),
              _TypeChip('▨ Pucca Non-Res', 'non_residential_pucca', _buildingType, (v) => setState(() => _buildingType = v)),
              _TypeChip('△ Kutcha Residential', 'kutcha_residential', _buildingType, (v) => setState(() => _buildingType = v)),
              _TypeChip('▲ Kutcha Non-Res', 'kutcha_non_residential', _buildingType, (v) => setState(() => _buildingType = v)),
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
                    labelText: 'Number (${widget.suggestedLabel})',
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
              widget.onConfirm(
                buildingType: _buildingType,
                buildingNumber: int.tryParse(_numCtrl.text) ?? widget.suggestedNumber,
                censusHouseCount: _houseCount,
              );
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
            ),
            child: const Text('CONFIRM', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              widget.onReject();
              Navigator.pop(context);
            },
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('IGNORE'),
          ),
        ],
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

class _LandmarkSheet extends StatefulWidget {
  const _LandmarkSheet({required this.candidate, required this.onConfirm, required this.onReject});
  final DiscoveryCandidate candidate;
  final DiscoveryConfirmCallback onConfirm;
  final VoidCallback onReject;

  @override
  State<_LandmarkSheet> createState() => _LandmarkSheetState();
}

class _LandmarkSheetState extends State<_LandmarkSheet> {
  late final TextEditingController _nameCtrl;
  late var _landmarkType = 'other';

  @override
  void initState() {
    super.initState();
    final c = widget.candidate;
    _landmarkType = HlbOfficialCatalog.guessLandmarkTypeFromLabel(c.label);
    _nameCtrl = TextEditingController(text: c.label);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.6;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Possible map feature', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
                  Text('Should I add this?', style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Label on HLB map',
                  labelStyle: TextStyle(color: Colors.white54),
                ),
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
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      widget.onConfirm(
                        buildingType: _landmarkType,
                        buildingNumber: 0,
                        censusHouseCount: 0,
                        featureLabel: _nameCtrl.text.trim(),
                      );
                      Navigator.pop(context);
                    },
                    child: const Text('CONFIRM ON HLB MAP'),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onReject();
                      Navigator.pop(context);
                    },
                    child: const Text('IGNORE'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
