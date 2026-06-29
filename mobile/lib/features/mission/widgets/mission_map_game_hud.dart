import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' hide LatLng;
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';

/// Google map basemap options exposed in the layers HUD.
enum MissionMapBasemap { hybrid, satellite, normal, terrain }

extension MissionMapBasemapX on MissionMapBasemap {
  MapType get googleType => switch (this) {
        MissionMapBasemap.hybrid => MapType.hybrid,
        MissionMapBasemap.satellite => MapType.satellite,
        MissionMapBasemap.normal => MapType.normal,
        MissionMapBasemap.terrain => MapType.terrain,
      };

  String get label => switch (this) {
        MissionMapBasemap.hybrid => 'Hybrid',
        MissionMapBasemap.satellite => 'Satellite',
        MissionMapBasemap.normal => 'Map',
        MissionMapBasemap.terrain => 'Terrain',
      };

  IconData get icon => switch (this) {
        MissionMapBasemap.hybrid => Icons.layers,
        MissionMapBasemap.satellite => Icons.satellite_alt,
        MissionMapBasemap.normal => Icons.map_outlined,
        MissionMapBasemap.terrain => Icons.terrain,
      };
}

enum MapNudgeDirection { north, south, east, west }

/// FPS-style floating stick: drag knob within ring, emits normalized vector (−1…1).
class MissionMapVirtualJoystick extends StatefulWidget {
  const MissionMapVirtualJoystick({
    required this.enabled,
    required this.onStickChanged,
    this.size = 112,
    this.label,
    this.labelColor,
    this.onCenterTap,
    super.key,
  });

  final bool enabled;
  final ValueChanged<Offset> onStickChanged;
  final double size;
  final String? label;
  final Color? labelColor;
  final VoidCallback? onCenterTap;

  @override
  State<MissionMapVirtualJoystick> createState() => _MissionMapVirtualJoystickState();
}

class _MissionMapVirtualJoystickState extends State<MissionMapVirtualJoystick> {
  Offset _knob = Offset.zero;

  double get _maxKnobTravel => widget.size * 0.38;

  Offset _clampKnob(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final delta = local - center;
    if (delta.distance <= _maxKnobTravel) return delta;
    return Offset.fromDirection(delta.direction, _maxKnobTravel);
  }

  Offset get _normalized {
    if (_maxKnobTravel <= 0) return Offset.zero;
    return Offset(_knob.dx / _maxKnobTravel, _knob.dy / _maxKnobTravel);
  }

  void _updateKnob(Offset local) {
    if (!widget.enabled) return;
    setState(() => _knob = _clampKnob(local));
    widget.onStickChanged(_normalized);
  }

  void _resetKnob() {
    if (_knob == Offset.zero) return;
    setState(() => _knob = Offset.zero);
    widget.onStickChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.size / 2;
    final knobSize = widget.size * 0.28;
    final labelColor = widget.labelColor ?? Colors.white70;

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.35,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  widget.label!,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => _updateKnob(d.localPosition),
                onPanUpdate: (d) => _updateKnob(d.localPosition),
                onPanEnd: (_) => _resetKnob(),
                onPanCancel: _resetKnob,
                onTapUp: (_) {
                  if (widget.onCenterTap != null && _knob.distance < 4) {
                    widget.onCenterTap!();
                  }
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.28),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
                      ),
                    ),
                    Transform.translate(
                      offset: _knob,
                      child: Container(
                        width: knobSize,
                        height: knobSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: widget.enabled ? 0.82 : 0.35),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.onCenterTap != null)
                      Positioned(
                        left: center - 10,
                        top: center - 10,
                        child: const SizedBox(width: 20, height: 20),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Vertical space for a HUD panel below the top toolbar row (status + layer toggle).
double missionMapHudMaxPanelHeight(
  BuildContext context, {
  double topOffset = 56,
  double bottomReserved = 0,
}) {
  final media = MediaQuery.of(context);
  final available = media.size.height -
      media.padding.top -
      topOffset -
      media.padding.bottom -
      bottomReserved;
  return available.clamp(96, media.size.height * 0.62);
}

/// Right-edge column: layers toggle + panel (240) + margin. Bottom HUDs stay left of this.
const double missionMapRightHudGutter = 256;

/// Bottom chrome height so the layers panel stops above map footers.
double missionMapBottomChromeHeight({
  bool lineDrawMode = false,
  bool showBottomBar = false,
  bool showNavBanner = false,
  bool showFineTuneBar = false,
}) {
  var height = 16.0;
  if (showNavBanner) height += 72;
  if (lineDrawMode) {
    height += 148;
  } else if (showFineTuneBar) {
    height += 80;
  } else if (showBottomBar) {
    height += 68;
  }
  return height;
}

/// Semi-transparent HUD panel anchored to map corners.
class MissionMapHudPanel extends StatelessWidget {
  const MissionMapHudPanel({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.maxWidth = 220,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      elevation: 8,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      ),
    );
  }
}

/// Compact mission status chip for top-left HUD.
class MissionMapHudStatus extends StatelessWidget {
  const MissionMapHudStatus({
    required this.title,
    required this.subtitle,
    this.icon = Icons.pentagon_outlined,
    this.progressPercent,
    this.questLabel,
    this.compact = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int? progressPercent;
  final String? questLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final phaseLine = questLabel ?? subtitle;

    return MissionMapHudPanel(
      maxWidth: compact ? 240 : 280,
      padding: compact ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8) : const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: const Color(0xFF42A5F5)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (progressPercent != null && compact)
                Text(
                  '$progressPercent%',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF00E676)),
                ),
            ],
          ),
          if (phaseLine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              phaseLine,
              style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, height: 1.25),
              maxLines: compact ? 2 : 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (progressPercent != null && !compact) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressPercent!.clamp(0, 100) / 100,
                minHeight: 6,
                backgroundColor: Colors.white12,
                color: const Color(0xFF00E676),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$progressPercent% mapped',
              style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Directional pad for fine corner nudging (meters per step).
class MissionMapNudgePad extends StatefulWidget {
  const MissionMapNudgePad({
    required this.enabled,
    required this.cornerLabel,
    required this.stepMeters,
    required this.onStepChanged,
    required this.onNudge,
    this.stepChoices = defaultStepChoices,
    this.stepUnit = 'm',
    this.compact = false,
    this.gameStyle = false,
    super.key,
  });

  final bool enabled;
  final String cornerLabel;
  final double stepMeters;
  final ValueChanged<double> onStepChanged;
  final ValueChanged<MapNudgeDirection> onNudge;
  final List<double> stepChoices;
  final String stepUnit;
  final bool compact;
  final bool gameStyle;

  static const defaultStepChoices = [0.5, 1.0, 2.0, 5.0];
  static const pixelStepChoices = [2.0, 5.0, 10.0, 20.0];

  @override
  State<MissionMapNudgePad> createState() => _MissionMapNudgePadState();
}

class _MissionMapNudgePadState extends State<MissionMapNudgePad> {
  Timer? _repeatTimer;
  MapNudgeDirection? _repeatDir;

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  void _cycleStep() {
    if (!widget.enabled || widget.stepChoices.isEmpty) return;
    final idx = widget.stepChoices.indexWhere((s) => (widget.stepMeters - s).abs() < 0.01);
    final next = widget.stepChoices[(idx + 1) % widget.stepChoices.length];
    widget.onStepChanged(next);
  }

  void _startRepeat(MapNudgeDirection dir) {
    if (!widget.enabled) return;
    _stopRepeat();
    _repeatDir = dir;
    widget.onNudge(dir);
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final d = _repeatDir;
      if (d != null) widget.onNudge(d);
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _repeatDir = null;
  }

  Widget _arrow(MapNudgeDirection dir, IconData icon, {double size = 40}) {
    return _NudgeButton(
      enabled: widget.enabled,
      icon: icon,
      size: size,
      onTap: () => widget.onNudge(dir),
      onHoldStart: () => _startRepeat(dir),
      onHoldEnd: _stopRepeat,
    );
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.gameStyle;
    final compactGame = game && widget.compact;
    final arrowSize = compactGame ? 32.0 : (game ? 36.0 : 40.0);
    final centerSize = compactGame ? 32.0 : (game ? 36.0 : 34.0);
    final panelWidth = compactGame ? 118.0 : (game ? 140.0 : 168.0);
    final centerLabel = widget.enabled ? widget.cornerLabel : '?';

    return MissionMapHudPanel(
      maxWidth: panelWidth,
      padding: EdgeInsets.fromLTRB(game ? 6 : 10, game ? 6 : 8, game ? 6 : 10, game ? 8 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!game && !widget.compact)
            Text(
              widget.enabled ? widget.cornerLabel : 'Tap a blue corner',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: widget.enabled ? const Color(0xFFFF9800) : AppTheme.textSecondary,
              ),
            ),
          if (!game && !widget.compact) const SizedBox(height: 6),
          _arrow(MapNudgeDirection.north, Icons.keyboard_arrow_up, size: arrowSize),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _arrow(MapNudgeDirection.west, Icons.keyboard_arrow_left, size: arrowSize),
              GestureDetector(
                onTap: widget.enabled && (widget.compact || game) ? _cycleStep : null,
                child: Container(
                  width: centerSize,
                  height: centerSize,
                  margin: EdgeInsets.symmetric(horizontal: compactGame ? 2 : 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.enabled
                        ? const Color(0xFF42A5F5).withValues(alpha: game ? 0.35 : 0.25)
                        : Colors.white10,
                    border: Border.all(
                      color: widget.enabled
                          ? (game ? const Color(0xFF42A5F5) : const Color(0xFFFF9800))
                          : Colors.white24,
                      width: game ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    centerLabel,
                    style: TextStyle(
                      fontSize: game ? 13 : 10,
                      fontWeight: FontWeight.w900,
                      color: widget.enabled ? Colors.white : Colors.white38,
                      height: 1,
                    ),
                  ),
                ),
              ),
              _arrow(MapNudgeDirection.east, Icons.keyboard_arrow_right, size: arrowSize),
            ],
          ),
          _arrow(MapNudgeDirection.south, Icons.keyboard_arrow_down, size: arrowSize),
          if (!widget.compact && !game) ...[
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 4,
              children: [
                const Text('Step', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                for (final m in widget.stepChoices)
                  ChoiceChip(
                    label: Text(
                      '${m == m.roundToDouble() ? m.toInt() : m}${widget.stepUnit}',
                      style: const TextStyle(fontSize: 10),
                    ),
                    selected: (widget.stepMeters - m).abs() < 0.01,
                    onSelected: widget.enabled ? (_) => widget.onStepChanged(m) : null,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Scale / rotate step controls for PDF ground overlay alignment.
class MissionMapPdfAdjustControls extends StatelessWidget {
  const MissionMapPdfAdjustControls({
    required this.enabled,
    required this.scaleStepPct,
    required this.rotateStepDeg,
    required this.onScaleStepChanged,
    required this.onRotateStepChanged,
    required this.onScaleDown,
    required this.onScaleUp,
    required this.onRotateLeft,
    required this.onRotateRight,
    super.key,
  });

  final bool enabled;
  final double scaleStepPct;
  final double rotateStepDeg;
  final ValueChanged<double> onScaleStepChanged;
  final ValueChanged<double> onRotateStepChanged;
  final VoidCallback onScaleDown;
  final VoidCallback onScaleUp;
  final VoidCallback onRotateLeft;
  final VoidCallback onRotateRight;

  static const scaleSteps = [0.5, 1.0, 2.0, 5.0];
  static const rotateSteps = [0.25, 0.5, 1.0, 2.0];

  Widget _stepBtn(String label, VoidCallback? onTap) {
    return Material(
      color: enabled ? const Color(0xFF1A1A28) : Colors.white10,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 32,
          child: Center(
            child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: enabled ? Colors.white : Colors.white38)),
          ),
        ),
      ),
    );
  }

  Widget _stepChips(List<double> steps, double selected, String suffix, ValueChanged<double> onChanged) {
    return Wrap(
      spacing: 4,
      runSpacing: 2,
      children: [
        for (final s in steps)
          ChoiceChip(
            label: Text('${s == s.roundToDouble() ? s.toInt() : s}$suffix', style: const TextStyle(fontSize: 9)),
            selected: (selected - s).abs() < 0.01,
            onSelected: enabled ? (_) => onChanged(s) : null,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.symmetric(horizontal: 5),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MissionMapHudPanel(
      maxWidth: 200,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            enabled ? 'PDF size & rotation' : 'PDF locked',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: enabled ? const Color(0xFF42A5F5) : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepBtn('−', enabled ? onScaleDown : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Scale', style: TextStyle(fontSize: 10, color: enabled ? Colors.white70 : Colors.white38)),
              ),
              _stepBtn('+', enabled ? onScaleUp : null),
            ],
          ),
          _stepChips(scaleSteps, scaleStepPct, '%', onScaleStepChanged),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stepBtn('↺', enabled ? onRotateLeft : null),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('Rotate', style: TextStyle(fontSize: 10, color: enabled ? Colors.white70 : Colors.white38)),
              ),
              _stepBtn('↻', enabled ? onRotateRight : null),
            ],
          ),
          _stepChips(rotateSteps, rotateStepDeg, '°', onRotateStepChanged),
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.enabled,
    required this.icon,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.size = 40,
  });

  final bool enabled;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconSize = (size * 0.55).clamp(16.0, 22.0);
    return Material(
      color: enabled ? const Color(0xFF1A1A28) : Colors.white10,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onHoldStart : null,
        onTapUp: (_) => onHoldEnd(),
        onTapCancel: onHoldEnd,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: size,
          height: size * 0.9,
          child: Icon(icon, size: iconSize, color: enabled ? Colors.white : Colors.white38),
        ),
      ),
    );
  }
}

/// Invisible full-screen tap target — place under HUD, above map, when layers panel is open.
class MissionMapLayersDismissBarrier extends StatelessWidget {
  const MissionMapLayersDismissBarrier({
    required this.visible,
    required this.onDismiss,
    super.key,
  });

  final bool visible;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDismiss,
      ),
    );
  }
}

/// Collapsible layer toggles for top-right HUD.
class MissionMapLayersDrawer extends StatelessWidget {
  const MissionMapLayersDrawer({
    required this.expanded,
    required this.onToggle,
    required this.showOfficialMap,
    required this.showRegionPins,
    required this.showBoundary,
    required this.showRoute,
    required this.showStartMarker,
    required this.showDraftBuildings,
    required this.showHlbLines,
    required this.showWalkPath,
    required this.showBasemap,
    required this.officialMapOpacity,
    required this.basemap,
    required this.onOfficialMapChanged,
    required this.onRegionPinsChanged,
    required this.onBoundaryChanged,
    required this.onRouteChanged,
    required this.onStartMarkerChanged,
    required this.onDraftBuildingsChanged,
    required this.onHlbLinesChanged,
    required this.onWalkPathChanged,
    required this.onBasemapVisibilityChanged,
    required this.onOpacityChanged,
    required this.onBasemapChanged,
    this.maxPanelHeight,
    super.key,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final bool showOfficialMap;
  final bool showRegionPins;
  final bool showBoundary;
  final bool showRoute;
  final bool showStartMarker;
  final bool showDraftBuildings;
  final bool showHlbLines;
  final bool showWalkPath;
  final bool showBasemap;
  final double officialMapOpacity;
  final MissionMapBasemap basemap;
  final ValueChanged<bool> onOfficialMapChanged;
  final ValueChanged<bool> onRegionPinsChanged;
  final ValueChanged<bool> onBoundaryChanged;
  final ValueChanged<bool> onRouteChanged;
  final ValueChanged<bool> onStartMarkerChanged;
  final ValueChanged<bool> onDraftBuildingsChanged;
  final ValueChanged<bool> onHlbLinesChanged;
  final ValueChanged<bool> onWalkPathChanged;
  final ValueChanged<bool> onBasemapVisibilityChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<MissionMapBasemap> onBasemapChanged;
  final double? maxPanelHeight;

  Widget _chip(String label, bool selected, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _layerPanelContent() {
    final hlbMapOn = showBoundary || showDraftBuildings || showHlbLines;

    void setHlbMap(bool on) {
      onBoundaryChanged(on);
      onDraftBuildingsChanged(on);
      onHlbLinesChanged(on);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _sectionHeader('HLB map', Icons.border_outer),
        _chip('Show HLB map', hlbMapOn, setHlbMap),
        if (hlbMapOn) ...[
          const SizedBox(height: 4),
          const Text(
            'Boundary and field drawings on satellite',
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          _chip('Boundary', showBoundary, onBoundaryChanged),
          _chip('Buildings & landmarks', showDraftBuildings, onDraftBuildingsChanged),
          _chip('Roads & canals', showHlbLines, onHlbLinesChanged),
          Theme(
            data: ThemeData(dividerColor: Colors.white12),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('More HLB layers', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              children: [
                _chip('Walk path', showWalkPath, onWalkPathChanged),
                _chip('Navigation route', showRoute, onRouteChanged),
                _chip('Start point', showStartMarker, onStartMarkerChanged),
                _chip('Region pins', showRegionPins, onRegionPinsChanged),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _sectionHeader('HLO scan', Icons.picture_as_pdf_outlined),
        _chip('Show map scan', showOfficialMap, onOfficialMapChanged),
        if (showOfficialMap) ...[
          const SizedBox(height: 4),
          const Text(
            'Map panel only — legend and title block are on HLB layout map',
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('Opacity', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
              Expanded(
                child: Slider(
                  value: officialMapOpacity,
                  min: 0.05,
                  max: 0.95,
                  onChanged: onOpacityChanged,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _sectionHeader('Google map', Icons.map_outlined),
        _chip('Show Google map', showBasemap, onBasemapVisibilityChanged),
        if (showBasemap) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final mode in MissionMapBasemap.values)
                ChoiceChip(
                  label: Text(mode.label, style: const TextStyle(fontSize: 10)),
                  selected: basemap == mode,
                  onSelected: (_) => onBasemapChanged(mode),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final panelMaxHeight = maxPanelHeight ?? missionMapHudMaxPanelHeight(context, bottomReserved: 120);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Icon(expanded ? Icons.layers : Icons.layers_outlined, color: Colors.white),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 240, maxHeight: panelMaxHeight),
            child: MissionMapHudPanel(
              maxWidth: 240,
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(10),
                child: _layerPanelContent(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Round icon button for HUD corners (fit, menu, my location).
class MissionMapHudIconButton extends StatelessWidget {
  const MissionMapHudIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Round HUD action button for bottom-right stack.
class MissionMapHudAction extends StatelessWidget {
  const MissionMapHudAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF42A5F5),
    this.enabled = true,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onPressed != null;
    return Material(
      color: active ? color.withValues(alpha: 0.92) : Colors.black54,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: active ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? Colors.white : Colors.white38),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

LatLng nudgeLatLng(LatLng point, MapNudgeDirection direction, double meters) {
  const mPerDegLat = 111320.0;
  final mPerDegLng = mPerDegLat * math.cos(point.latitude * math.pi / 180).abs().clamp(0.01, 1.0);
  return switch (direction) {
    MapNudgeDirection.north => LatLng(point.latitude + meters / mPerDegLat, point.longitude),
    MapNudgeDirection.south => LatLng(point.latitude - meters / mPerDegLat, point.longitude),
    MapNudgeDirection.east => LatLng(point.latitude, point.longitude + meters / mPerDegLng),
    MapNudgeDirection.west => LatLng(point.latitude, point.longitude - meters / mPerDegLng),
  };
}

/// Google Maps–style bottom bar: one primary action + compact utilities.
class MissionMapBottomBar extends StatelessWidget {
  const MissionMapBottomBar({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.primaryColor,
    required this.onPrimary,
    this.onMore,
    super.key,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final Color primaryColor;
  final VoidCallback onPrimary;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(16),
      elevation: 12,
      shadowColor: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: primaryColor,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onPrimary,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(primaryIcon, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            primaryLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onMore != null) ...[
              const SizedBox(width: 6),
              Material(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onMore,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Icon(Icons.more_horiz, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the crosshair will place when the enumerator taps Place.
enum MapPlaceTool { building, feature, line }

/// Center-crosshair placement HUD — pan, zoom, rotate, then place.
class MissionMapPlaceHud extends StatelessWidget {
  const MissionMapPlaceHud({
    required this.selected,
    required this.onToolSelected,
    required this.onPlace,
    this.onMore,
    super.key,
  });

  final MapPlaceTool selected;
  final ValueChanged<MapPlaceTool> onToolSelected;
  final VoidCallback onPlace;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      elevation: 12,
      shadowColor: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pan · zoom · rotate — crosshair marks the spot',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _toolChip(
                    icon: Icons.home_work_outlined,
                    label: 'Building',
                    tool: MapPlaceTool.building,
                    color: const Color(0xFF00E676),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _toolChip(
                    icon: Icons.place_outlined,
                    label: 'Feature',
                    tool: MapPlaceTool.feature,
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _toolChip(
                    icon: Icons.polyline_outlined,
                    label: 'Road',
                    tool: MapPlaceTool.line,
                    color: const Color(0xFF42A5F5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onPlace,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 20),
                    label: Text(
                      selected == MapPlaceTool.building
                          ? 'Place building'
                          : selected == MapPlaceTool.feature
                              ? 'Place feature'
                              : 'Start road',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: switch (selected) {
                        MapPlaceTool.building => const Color(0xFF00E676),
                        MapPlaceTool.feature => Colors.orange,
                        MapPlaceTool.line => const Color(0xFF42A5F5),
                      },
                      foregroundColor: Colors.black,
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                if (onMore != null) ...[
                  const SizedBox(width: 6),
                  Material(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onMore,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.more_horiz, color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolChip({
    required IconData icon,
    required String label,
    required MapPlaceTool tool,
    required Color color,
  }) {
    final active = selected == tool;
    return Material(
      color: active ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onToolSelected(tool),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? color : Colors.white12, width: active ? 2 : 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: active ? color : Colors.white54),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: active ? Colors.white : Colors.white54,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Map-center aim reticle (roads, buildings, landmarks).
class MissionMapCrosshair extends StatelessWidget {
  const MissionMapCrosshair({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(56, 56),
      painter: _MissionMapCrosshairPainter(),
    );
  }
}

class _MissionMapCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..color = const Color(0xFF42A5F5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final line = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, 22, ring);
    canvas.drawLine(Offset(center.dx, 4), Offset(center.dx, center.dy - 6), line);
    canvas.drawLine(Offset(center.dx, center.dy + 6), Offset(center.dx, size.height - 4), line);
    canvas.drawLine(Offset(4, center.dy), Offset(center.dx - 6, center.dy), line);
    canvas.drawLine(Offset(center.dx + 6, center.dy), Offset(size.width - 4, center.dy), line);
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFF42A5F5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Bottom bar while fine-tuning a landmark position on the HLB map.
class MissionLandmarkFineTuneBar extends StatelessWidget {
  const MissionLandmarkFineTuneBar({
    required this.landmarkName,
    required this.onSave,
    required this.onCancel,
    super.key,
  });

  final String landmarkName;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.place_outlined, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fine-tune: $landmarkName',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Drag the orange dot, then save',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onCancel, child: const Text('Cancel')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Save position'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Overflow menu for secondary mission tools (draft map, listing, analytics).
Future<void> showMissionMoreSheet(
  BuildContext context, {
  required List<MissionMoreSheetItem> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.55;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 8),
              for (final item in items)
                ListTile(
                  leading: Icon(item.icon, color: Colors.white70, size: 22),
                  title: Text(item.label, style: const TextStyle(fontSize: 14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    item.onTap();
                  },
                ),
            ],
          ),
        ),
      );
    },
  );
}

class MissionMoreSheetItem {
  const MissionMoreSheetItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

