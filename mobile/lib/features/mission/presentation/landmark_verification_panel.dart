import 'package:flutter/material.dart';

import '../../../core/maps/google_geocoding_service.dart';
import '../../../core/maps/google_places_service.dart';
import '../../../core/theme/app_theme.dart';
import '../data/landmark_anchor_service.dart';
import '../data/mission_seed_location_resolver.dart';
import '../models/landmark_anchor_models.dart';
import '../widgets/ocr_label_map_editor.dart';

/// User confirms OCR labels from the official map match real Google Places locations.
class LandmarkVerificationPanel extends StatefulWidget {
  const LandmarkVerificationPanel({
    required this.layoutImagePath,
    required this.rows,
    required this.ocrLabelCount,
    required this.seed,
    required this.onSearchPlaces,
    required this.onContinue,
    required this.onSkip,
    super.key,
  });

  final String layoutImagePath;
  final List<LandmarkMatchRow> rows;
  final int ocrLabelCount;
  final MissionSeedLocation seed;
  final Future<List<PlaceMatchCandidate>> Function(String labelText) onSearchPlaces;
  final void Function(List<LandmarkMatchRow> confirmedRows) onContinue;
  final VoidCallback onSkip;

  @override
  State<LandmarkVerificationPanel> createState() => _LandmarkVerificationPanelState();
}

class _LandmarkVerificationPanelState extends State<LandmarkVerificationPanel> {
  late List<LandmarkMatchRow> _rows;
  String? _selectedLabelId;
  final _textControllers = <String, TextEditingController>{};
  final _searchingIds = <String>{};
  var _initialSearchDone = false;
  String? _apiHint;
  var _mapExpanded = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.rows.map((r) => r.copyWith()).toList();
    if (_rows.isNotEmpty) _selectedLabelId = _rows.first.label.id;
    for (final row in _rows) {
      _textControllers[row.label.id] = TextEditingController(text: row.label.text);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _searchAllRows());
  }

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<MapTextLabel> get _labels => _rows.map((r) => r.label).toList();

  int get _confirmedCount => _rows.where((r) => r.isReady).length;

  bool get _canContinue => _confirmedCount >= LandmarkAnchorService.minLabelsForVerification;

  void _updateRow(int index, LandmarkMatchRow row) {
    setState(() => _rows[index] = row);
  }

  void _selectLabel(String id) => setState(() => _selectedLabelId = id);

  void _moveLabel(String id, double uvX, double uvY) {
    final index = _rows.indexWhere((r) => r.label.id == id);
    if (index < 0) return;
    final row = _rows[index];
    _updateRow(
      index,
      row.copyWith(
        label: row.label.copyWith(uvX: uvX, uvY: uvY),
        confirmed: false,
      ),
    );
  }

  Future<void> _searchAllRows() async {
    if (_initialSearchDone) return;
    _initialSearchDone = true;
    resetPlacesApiStatus();
    resetGeocodingApiStatus();
    await Future.wait([for (var i = 0; i < _rows.length; i++) _searchPlaces(i)]);
    if (!mounted) return;
    if (placesApiAccessDenied || geocodingApiAccessDenied) {
      setState(() => _apiHint = _buildApiHint());
    }
  }

  String _buildApiHint() {
    final denied = <String>[];
    if (placesApiAccessDenied) denied.add('Places API');
    if (geocodingApiAccessDenied) denied.add('Geocoding API');
    final apis = denied.join(' and ');
    final town = widget.seed.metadata?.townVillage ?? 'the PDF address';
    final skipNote = widget.seed.source == MissionSeedSource.pdfMetadata
        ? 'Skip will place using $town from the PDF sidebar.'
        : geocodingApiAccessDenied
            ? 'Skip will fall back to your current GPS until Geocoding API is enabled.'
            : 'Or tap Skip to place using $town from the PDF sidebar.';
    return '$apis not enabled for this Google Cloud key. '
        'In console.cloud.google.com → APIs & Services → Library, enable $apis '
        'on the same project as your Maps SDK key, then hot restart. $skipNote';
  }

  String get _skipLabel {
    final town = widget.seed.metadata?.townVillage;
    if (widget.seed.source == MissionSeedSource.pdfMetadata && town != null) {
      return 'Skip — place using $town from PDF sidebar';
    }
    if (geocodingApiAccessDenied) {
      return 'Skip — place at my current GPS (enable Geocoding for $town)';
    }
    return 'Skip — use address from PDF sidebar';
  }

  Future<void> _searchPlaces(int index) async {
    final row = _rows[index];
    final text = _textControllers[row.label.id]?.text.trim() ?? row.label.text;
    if (text.length < 3) return;

    setState(() => _searchingIds.add(row.label.id));
    try {
      final suggestions = await widget.onSearchPlaces(text);
      if (!mounted) return;
      _updateRow(
        index,
        row.copyWith(
          label: row.label.copyWith(text: text),
          suggestions: suggestions,
          selected: suggestions.isNotEmpty ? suggestions.first : null,
          confirmed: false,
        ),
      );
    } finally {
      if (mounted) setState(() => _searchingIds.remove(row.label.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    final mapHeight = _mapExpanded ? screenH * 0.28 : 108.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify landmarks',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${widget.ocrLabelCount} labels · $_confirmedCount/${LandmarkAnchorService.minLabelsForVerification} confirmed',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.2),
                    ),
                    if (_searchingIds.isNotEmpty)
                      const Text(
                        'Searching Google…',
                        style: TextStyle(color: Color(0xFF42A5F5), fontSize: 10, height: 1.2),
                      ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _mapExpanded = !_mapExpanded),
                icon: Icon(_mapExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(_mapExpanded ? 'Shrink map' : 'Expand map', style: const TextStyle(fontSize: 11)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: mapHeight,
            child: OcrLabelMapEditor(
              imagePath: widget.layoutImagePath,
              labels: _labels,
              selectedLabelId: _selectedLabelId,
              onLabelSelected: _selectLabel,
              onLabelMoved: _moveLabel,
              compact: !_mapExpanded,
            ),
          ),
        ),
        if (_apiHint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Text(
              _apiHint!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 10, height: 1.25),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            itemCount: _rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final row = _rows[index];
              final selected = row.label.id == _selectedLabelId;
              return _MatchCard(
                row: row,
                selected: selected,
                textController: _textControllers[row.label.id]!,
                searching: _searchingIds.contains(row.label.id),
                onTap: () => _selectLabel(row.label.id),
                onChanged: (next) => _updateRow(index, next),
                onSearch: () => _searchPlaces(index),
              );
            },
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 6 + bottomInset),
          decoration: const BoxDecoration(
            color: Color(0xFF0A0A10),
            border: Border(top: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 42,
                child: ElevatedButton(
                  onPressed: _canContinue
                      ? () {
                          final confirmed = <LandmarkMatchRow>[];
                          for (final row in _rows.where((r) => r.isReady)) {
                            final text = _textControllers[row.label.id]?.text.trim() ?? row.label.text;
                            confirmed.add(row.copyWith(label: row.label.copyWith(text: text)));
                          }
                          widget.onContinue(confirmed);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white12,
                  ),
                  child: const Text('PLACE HLB USING MATCHES', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 36,
                child: TextButton(
                  onPressed: widget.onSkip,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(_skipLabel, style: const TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.row,
    required this.selected,
    required this.textController,
    required this.searching,
    required this.onTap,
    required this.onChanged,
    required this.onSearch,
  });

  final LandmarkMatchRow row;
  final bool selected;
  final TextEditingController textController;
  final bool searching;
  final VoidCallback onTap;
  final ValueChanged<LandmarkMatchRow> onChanged;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final pinLabel = '${(row.label.uvX * 100).toStringAsFixed(0)}%, ${(row.label.uvY * 100).toStringAsFixed(0)}%';
    final hasMatch = row.suggestions.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1A2420) : const Color(0xFF14141E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: row.confirmed
                  ? const Color(0xFF00E676).withValues(alpha: 0.5)
                  : selected
                      ? const Color(0xFF42A5F5).withValues(alpha: 0.45)
                      : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TextField(
                      controller: textController,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Landmark text',
                        hintStyle: const TextStyle(fontSize: 12),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        filled: true,
                        fillColor: const Color(0xFF1A1A2E),
                        border: const OutlineInputBorder(),
                      ),
                      onTap: onTap,
                      onChanged: (_) => onChanged(row.copyWith(confirmed: false)),
                    ),
                  ),
                  IconButton(
                    onPressed: searching ? null : onSearch,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search, size: 18),
                    tooltip: 'Search again',
                  ),
                  Checkbox(
                    value: row.confirmed,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    activeColor: const Color(0xFF00E676),
                    onChanged: row.selected == null
                        ? null
                        : (v) => onChanged(row.copyWith(confirmed: v ?? false)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.pin_drop_outlined, size: 12, color: AppTheme.textSecondary.withValues(alpha: 0.8)),
                  const SizedBox(width: 4),
                  Text(pinLabel, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  const Spacer(),
                  if (!hasMatch && !searching)
                    const Flexible(
                      child: Text(
                        'No match',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
                      ),
                    ),
                ],
              ),
              if (hasMatch) ...[
                const SizedBox(height: 4),
                DropdownButtonFormField<PlaceMatchCandidate>(
                  value: row.selected,
                  dropdownColor: const Color(0xFF1A1A2E),
                  isExpanded: true,
                  isDense: true,
                  menuMaxHeight: 280,
                  itemHeight: 52,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF1A1A2E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  selectedItemBuilder: (context) => [
                    for (final s in row.suggestions)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                        ),
                      ),
                  ],
                  items: [
                    for (final s in row.suggestions)
                      DropdownMenuItem(
                        value: s,
                        child: Text(
                          '${s.name}\n${s.address}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.2),
                        ),
                      ),
                  ],
                  onChanged: (candidate) {
                    if (candidate == null) return;
                    onChanged(row.copyWith(selected: candidate, confirmed: row.confirmed));
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
