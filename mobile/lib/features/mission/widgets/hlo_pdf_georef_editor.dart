import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Tangent;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart' hide Path;

import '../../../core/storage/mission_layout_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../models/pdf_georef_models.dart';
import 'mission_layout_image.dart';
import 'mission_map_game_hud.dart';
import 'ocr_label_map_editor.dart';
import 'pin_places_autocomplete_field.dart';

const _kPinWidth = 36.0;
const _kPinHeight = 48.0;

/// Interactive HLO PDF: zoom, rotate, trace boundary, place pins, match Places.
class HloPdfGeorefEditor extends StatefulWidget {
  const HloPdfGeorefEditor({
    required this.imagePath,
    required this.boundaryRing,
    required this.pins,
    required this.placesBias,
    required this.onTrackBoundary,
    required this.onPinAdded,
    required this.onPinUpdated,
    required this.onPinRemoved,
    required this.onShowSatellite,
    required this.canShowSatellite,
    this.imageBytes,
    this.onBack,
    this.isTrackingBoundary = false,
    this.retraceOnly = false,
    super.key,
  });

  final String imagePath;
  final Uint8List? imageBytes;
  final VoidCallback? onBack;
  final List<({double x, double y})> boundaryRing;
  final List<PdfGeorefPin> pins;
  final LatLng? placesBias;
  final Future<void> Function() onTrackBoundary;
  final ValueChanged<PdfGeorefPin> onPinAdded;
  final void Function(PdfGeorefPin pin) onPinUpdated;
  final ValueChanged<int> onPinRemoved;
  final VoidCallback onShowSatellite;
  final bool canShowSatellite;
  final bool isTrackingBoundary;
  final bool retraceOnly;

  @override
  State<HloPdfGeorefEditor> createState() => _HloPdfGeorefEditorState();
}

class _HloPdfGeorefEditorState extends State<HloPdfGeorefEditor> with SingleTickerProviderStateMixin {
  final _stackKey = GlobalKey();
  final _overlayKey = GlobalKey();
  final _transformController = TransformationController();
  Size? _imageSize;
  var _rotation = 0.0;
  var _pinMode = false;
  int? _draggingPinNumber;
  int? _selectedPinNumber;
  var _searchFocused = false;
  late final AnimationController _boundaryRevealController;
  late final Animation<double> _boundaryReveal;

  static const _boundaryRevealDuration = Duration(milliseconds: 3000);

  @override
  void initState() {
    super.initState();
    _boundaryRevealController = AnimationController(
      vsync: this,
      duration: _boundaryRevealDuration,
    );
    _boundaryReveal = CurvedAnimation(
      parent: _boundaryRevealController,
      curve: Curves.easeInOutCubic,
    )..addListener(() => setState(() {}));
    _transformController.addListener(_onTransformChanged);
    _loadImageSize();
    if (widget.pins.isNotEmpty) {
      _selectedPinNumber = widget.pins.first.number;
    }
    if (widget.boundaryRing.length >= 3) {
      _boundaryRevealController.value = 1;
    }
  }

  @override
  void dispose() {
    _boundaryRevealController.dispose();
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    super.dispose();
  }

  void _replayBoundaryReveal() {
    _boundaryRevealController
      ..reset()
      ..forward();
  }

  bool get _boundaryRevealComplete => _boundaryReveal.value >= 1.0;

  void _onTransformChanged() => setState(() {});

  void _rotateStep({bool reverse = false}) {
    setState(() => _rotation += (reverse ? -1 : 1) * 0.06);
  }

  @override
  void didUpdateWidget(HloPdfGeorefEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _loadImageSize();
      _boundaryRevealController.value = 0;
    }
    if (widget.boundaryRing.length >= 3 && widget.boundaryRing != oldWidget.boundaryRing) {
      _replayBoundaryReveal();
    } else if (widget.boundaryRing.length < 3 && oldWidget.boundaryRing.length >= 3) {
      _boundaryRevealController.value = 0;
    }
    if (widget.pins.length > oldWidget.pins.length) {
      _selectedPinNumber = widget.pins.last.number;
    }
    if (_selectedPinNumber != null && !widget.pins.any((p) => p.number == _selectedPinNumber)) {
      _selectedPinNumber = widget.pins.isEmpty ? null : widget.pins.first.number;
    }
    if (_selectedPinNumber == null && widget.pins.isNotEmpty) {
      _selectedPinNumber = widget.pins.first.number;
    }
  }

  PdfGeorefPin? get _selectedPin {
    final n = _selectedPinNumber;
    if (n == null) return null;
    for (final p in widget.pins) {
      if (p.number == n) return p;
    }
    return null;
  }

  Future<void> _loadImageSize() async {
    final bytes = widget.imageBytes ?? await readMissionLayoutBytes(widget.imagePath);
    if (bytes == null) return;
    final decoded = img.decodeImage(bytes);
    if (!mounted || decoded == null) return;
    setState(() => _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble()));
  }

  Widget _layoutImageWidget() {
    if (widget.imageBytes != null) {
      return Image.memory(widget.imageBytes!, fit: BoxFit.contain);
    }
    return MissionLayoutImage(ref: widget.imagePath, fit: BoxFit.contain);
  }

  void _resetView() {
    _transformController.value = Matrix4.identity();
    setState(() => _rotation = 0);
  }

  Offset _inverseRotate(Offset local, Size size, double angle) {
    if (angle == 0) return local;
    final center = Offset(size.width / 2, size.height / 2);
    final translated = local - center;
    final cos = math.cos(-angle);
    final sin = math.sin(-angle);
    return Offset(
      translated.dx * cos - translated.dy * sin,
      translated.dx * sin + translated.dy * cos,
    ) + center;
  }

  Offset _rotateAround(Offset point, Offset center, double angle) {
    if (angle == 0) return point;
    final translated = point - center;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    return Offset(
      translated.dx * cos - translated.dy * sin,
      translated.dx * sin + translated.dy * cos,
    ) + center;
  }

  /// Map UV → screen coords including rotation + InteractiveViewer zoom/pan.
  Offset? _pinScreenPosition(ImageCoordMapper mapper, double uvX, double uvY, Size containerSize) {
    var display = mapper.uvToDisplay(uvX, uvY);
    display = _rotateAround(display, Offset(containerSize.width / 2, containerSize.height / 2), _rotation);
    return MatrixUtils.transformPoint(_transformController.value, display);
  }

  Offset _screenLocalToUv(Offset screenLocal, ImageCoordMapper mapper, Size containerSize) {
    final inverseTransform = Matrix4.inverted(_transformController.value);
    final displayLocal = MatrixUtils.transformPoint(inverseTransform, screenLocal);
    final unrotated = _inverseRotate(displayLocal, containerSize, _rotation);
    return mapper.displayToUv(unrotated);
  }

  void _movePin(PdfGeorefPin pin, Offset globalPosition, ImageCoordMapper mapper, Size containerSize) {
    final box = _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final uv = _screenLocalToUv(local, mapper, containerSize);
    widget.onPinUpdated(pin.copyWith(uvX: uv.dx, uvY: uv.dy));
  }

  void _handleTap(Offset globalPosition, ImageCoordMapper mapper, Size containerSize) {
    if (!_pinMode) return;
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(globalPosition);
    final unrotated = _inverseRotate(local, containerSize, _rotation);
    final uv = mapper.displayToUv(unrotated);

    widget.onPinAdded(
      PdfGeorefPin(
        number: widget.pins.length + 1,
        uvX: uv.dx,
        uvY: uv.dy,
      ),
    );
    setState(() => _pinMode = false);
  }

  Widget _buildMapCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imageSize = _imageSize;
        final mapper = imageSize == null
            ? null
            : ImageCoordMapper(containerSize: containerSize, imageSize: imageSize);
        final hasBoundary = widget.boundaryRing.length >= 3;

        return Stack(
          key: _overlayKey,
          clipBehavior: Clip.hardEdge,
          children: [
            InteractiveViewer(
              transformationController: _transformController,
              minScale: 0.4,
              maxScale: 10,
              panEnabled: !_pinMode,
              scaleEnabled: !_pinMode,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapUp: mapper == null
                    ? null
                    : (details) => _handleTap(details.globalPosition, mapper, containerSize),
                child: Transform.rotate(
                  angle: _rotation,
                  child: Stack(
                    key: _stackKey,
                    fit: StackFit.expand,
                    children: [
                      _layoutImageWidget(),
                      if (mapper != null && hasBoundary)
                        CustomPaint(
                          painter: _BoundaryPainter(
                            ring: widget.boundaryRing,
                            mapper: mapper,
                            revealProgress: _boundaryReveal.value,
                          ),
                          size: containerSize,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (mapper != null)
              ...() {
                final sorted = [...widget.pins];
                if (_selectedPinNumber != null) {
                  sorted.sort((a, b) {
                    if (a.number == _selectedPinNumber) return 1;
                    if (b.number == _selectedPinNumber) return -1;
                    return a.number.compareTo(b.number);
                  });
                }
                return sorted.map((pin) {
                  final tip = _pinScreenPosition(mapper, pin.uvX, pin.uvY, containerSize);
                  if (tip == null) return const SizedBox.shrink();

                  final selected = _selectedPinNumber == pin.number;

                  return Positioned(
                    left: tip.dx - _kPinWidth / 2,
                    top: tip.dy - _kPinHeight,
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedPinNumber = pin.number),
                      onPanStart: (_) => setState(() {
                        _draggingPinNumber = pin.number;
                        _selectedPinNumber = pin.number;
                      }),
                      onPanUpdate: (details) {
                        if (_draggingPinNumber == pin.number) {
                          _movePin(pin, details.globalPosition, mapper, containerSize);
                        }
                      },
                      onPanEnd: (_) => setState(() => _draggingPinNumber = null),
                      onPanCancel: () => setState(() => _draggingPinNumber = null),
                      child: _MapDropPin(
                        number: pin.number,
                        ready: pin.isReady,
                        selected: selected,
                        dragging: _draggingPinNumber == pin.number,
                        onRemove: () => widget.onPinRemoved(pin.number),
                      ),
                    ),
                  );
                });
              }(),
            if (widget.isTrackingBoundary)
              const _BoundaryScanOverlay(),
            if (hasBoundary && !_boundaryRevealComplete && !widget.isTrackingBoundary)
              _BoundaryRevealBanner(progress: _boundaryReveal.value),
            if (_pinMode)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFF42A5F5), width: 2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final readyPins = widget.pins.where((p) => p.isReady).length;
    final selected = _selectedPin;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final searchVisible = !widget.retraceOnly && selected != null;
    final bottomBarHeight = searchVisible ? 56.0 + bottomInset : bottomInset;
    final bottomHint = bottomBarHeight + 12;

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: const Color(0xFF050508),
          child: _buildMapCanvas(),
        ),
        if (widget.onBack != null)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: MissionMapHudIconButton(
              icon: Icons.arrow_back,
              tooltip: 'Back',
              onPressed: widget.onBack!,
            ),
          ),
        if (!widget.retraceOnly)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (widget.canShowSatellite)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _SatelliteLaunchOrb(
                      retrace: widget.retraceOnly,
                      onPressed: widget.onShowSatellite,
                    ),
                  ),
                _AddPinOrb(
                  active: _pinMode,
                  onPressed: () => setState(() => _pinMode = !_pinMode),
                ),
                const SizedBox(height: 8),
                MissionMapHudIconButton(
                  icon: Icons.rotate_right,
                  tooltip: 'Rotate map',
                  onPressed: _rotateStep,
                ),
                const SizedBox(height: 8),
                MissionMapHudIconButton(
                  icon: Icons.center_focus_strong,
                  tooltip: 'Reset view',
                  onPressed: _resetView,
                ),
              ],
            ),
          ),
        if (widget.retraceOnly && widget.canShowSatellite)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: _SatelliteLaunchOrb(
              retrace: true,
              onPressed: widget.onShowSatellite,
            ),
          ),
        if (!widget.retraceOnly && widget.pins.isNotEmpty)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 6,
            left: 0,
            right: 0,
            child: Center(
              child: _MatchProgressOrb(
                ready: readyPins,
                total: kMinGeorefMatchedPins,
                pinCount: widget.pins.length,
              ),
            ),
          ),
        if (!widget.retraceOnly && widget.pins.length > 1)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 38,
            left: 0,
            right: 0,
            child: _PinStrip(
              pins: widget.pins,
              selected: _selectedPinNumber,
              onSelect: (n) => setState(() => _selectedPinNumber = n),
            ),
          ),
        if (!_pinMode && !_searchFocused)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomHint,
            child: Center(
              child: Text(
                'Pinch to zoom · drag to pan',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        if (searchVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.black.withValues(alpha: 0.92),
              clipBehavior: Clip.none,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomInset),
                child: PinPlacesAutocompleteField(
                  key: ValueKey('pin_search_${selected.number}_${selected.place?.placeId}'),
                  pinNumber: selected.number,
                  value: selected.place,
                  initialSearchText: selected.searchText,
                  bias: widget.placesBias,
                  compact: true,
                  showPinBadge: false,
                  overlaySuggestions: false,
                  onFocusChanged: (focused) => setState(() => _searchFocused = focused),
                  onSelected: (place) {
                    widget.onPinUpdated(selected.copyWith(place: place, clearPlace: place == null));
                  },
                  onSearchTextChanged: (text) {
                    widget.onPinUpdated(selected.copyWith(searchText: text));
                  },
                ),
              ),
            ),
          ),
        if (_pinMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomHint + 118,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF42A5F5).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Tap landmark tip on map',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddPinOrb extends StatelessWidget {
  const _AddPinOrb({required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  static const _pinColor = Color(0xFFEA4335);
  static const _activeColor = Color(0xFF42A5F5);

  @override
  Widget build(BuildContext context) {
    final color = active ? _activeColor : _pinColor;

    return Material(
      color: Colors.transparent,
      elevation: active ? 10 : 6,
      shadowColor: color.withValues(alpha: 0.55),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 52,
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.location_on, size: 44, color: color),
              Positioned(
                top: 7,
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? Colors.white : Colors.white.withValues(alpha: 0.95),
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: Icon(Icons.add_rounded, size: 14, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatchProgressOrb extends StatelessWidget {
  const _MatchProgressOrb({
    required this.ready,
    required this.total,
    required this.pinCount,
  });

  final int ready;
  final int total;
  final int pinCount;

  @override
  Widget build(BuildContext context) {
    final done = ready >= total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? const Color(0xFF00E676) : Colors.white24),
      ),
      child: Text(
        done ? 'Ready · $ready' : '$ready/$total · $pinCount pins',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: done ? const Color(0xFF00E676) : Colors.white70,
        ),
      ),
    );
  }
}

class _PinStrip extends StatelessWidget {
  const _PinStrip({
    required this.pins,
    required this.selected,
    required this.onSelect,
  });

  final List<PdfGeorefPin> pins;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Row(
        children: [
          for (final pin in pins)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: GestureDetector(
                onTap: () => onSelect(pin.number),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected == pin.number
                        ? const Color(0xFF42A5F5)
                        : (pin.isReady ? const Color(0xFF34A853) : Colors.black54),
                    border: Border.all(
                      color: selected == pin.number ? Colors.white : Colors.white24,
                      width: selected == pin.number ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    '${pin.number}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SatelliteLaunchOrb extends StatelessWidget {
  const _SatelliteLaunchOrb({required this.retrace, required this.onPressed});

  final bool retrace;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF00E676),
      shape: const CircleBorder(),
      elevation: 10,
      shadowColor: const Color(0xFF00E676).withValues(alpha: 0.5),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: retrace ? 'Apply boundary trace' : 'Preview on satellite map',
          child: Semantics(
            button: true,
            label: retrace ? 'Apply boundary trace' : 'Preview on satellite map',
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                retrace ? Icons.check_rounded : Icons.satellite_alt,
                color: Colors.black,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoundaryScanOverlay extends StatefulWidget {
  const _BoundaryScanOverlay();

  @override
  State<_BoundaryScanOverlay> createState() => _BoundaryScanOverlayState();
}

class _BoundaryScanOverlayState extends State<_BoundaryScanOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scanController,
      builder: (context, child) {
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black.withValues(alpha: 0.28)),
            Align(
              alignment: Alignment(0, -1 + 2 * _scanController.value),
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      const Color(0xFF00E676).withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.45),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Scanning HLB border…',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BoundaryRevealBanner extends StatelessWidget {
  const _BoundaryRevealBanner({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final pct = (progress * 100).round().clamp(0, 100);
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 56,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFF1744).withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2,
                  color: const Color(0xFFFF1744),
                  backgroundColor: Colors.white24,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Tracing boundary… $pct%',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoundaryPainter extends CustomPainter {
  _BoundaryPainter({
    required this.ring,
    required this.mapper,
    this.revealProgress = 1.0,
  });

  final List<({double x, double y})> ring;
  final ImageCoordMapper mapper;
  final double revealProgress;

  Path _buildRingPath() {
    final path = Path();
    for (var i = 0; i < ring.length; i++) {
      final pt = mapper.uvToDisplay(ring[i].x, ring[i].y);
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ring.length < 2) return;

    final fullPath = _buildRingPath();
    final progress = revealProgress.clamp(0.0, 1.0);
    final metrics = fullPath.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final totalLength = metrics.fold<double>(0, (sum, m) => sum + m.length);
    final targetLength = totalLength * progress;

    final stroke = Paint()
      ..color = const Color(0xFFFF1744)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final glow = Paint()
      ..color = const Color(0xFFFF1744).withValues(alpha: 0.35)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final drawPath = Path();
    var consumed = 0.0;
    Tangent? tip;

    for (final metric in metrics) {
      if (consumed >= targetLength) break;
      final segmentLen = (targetLength - consumed).clamp(0.0, metric.length);
      drawPath.addPath(metric.extractPath(0, segmentLen), Offset.zero);
      tip = metric.getTangentForOffset(segmentLen);
      consumed += segmentLen;
    }

    canvas.drawPath(drawPath, glow);
    canvas.drawPath(drawPath, stroke);

    if (tip != null && progress > 0.02 && progress < 0.995) {
      final headGlow = Paint()
        ..color = const Color(0xFFFF5252).withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(tip.position, 7, headGlow);
      canvas.drawCircle(
        tip.position,
        4,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoundaryPainter oldDelegate) =>
      oldDelegate.ring != ring ||
      oldDelegate.mapper != mapper ||
      oldDelegate.revealProgress != revealProgress;
}

class _MapDropPin extends StatelessWidget {
  const _MapDropPin({
    required this.number,
    required this.ready,
    required this.onRemove,
    this.selected = false,
    this.dragging = false,
  });

  final int number;
  final bool ready;
  final bool selected;
  final bool dragging;
  final VoidCallback onRemove;

  static const _pinColor = Color(0xFFEA4335);
  static const _readyColor = Color(0xFF34A853);
  static const _selectedColor = Color(0xFF42A5F5);

  @override
  Widget build(BuildContext context) {
    final color = ready ? _readyColor : (selected ? _selectedColor : _pinColor);

    return GestureDetector(
      onLongPress: onRemove,
      child: SizedBox(
        width: _kPinWidth,
        height: _kPinHeight,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Icon(
              Icons.location_on,
              size: _kPinHeight,
              color: color,
              shadows: [
                Shadow(
                  color: dragging || selected ? Colors.white70 : Colors.black54,
                  blurRadius: dragging || selected ? 10 : 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            Positioned(
              top: 8,
              child: Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: selected ? 2 : 1.5),
                ),
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
