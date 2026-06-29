import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../core/theme/app_theme.dart';
import '../models/landmark_anchor_models.dart';

/// Maps between image UV (0–1) and on-screen coordinates for [BoxFit.contain].
class ImageCoordMapper {
  ImageCoordMapper({required this.containerSize, required this.imageSize});

  final Size containerSize;
  final Size imageSize;

  Rect get displayRect {
    final fitted = applyBoxFit(BoxFit.contain, imageSize, containerSize);
    return Alignment.center.inscribe(fitted.destination, Offset.zero & containerSize);
  }

  Offset uvToDisplay(double u, double v) {
    final r = displayRect;
    return Offset(r.left + u * r.width, r.top + v * r.height);
  }

  Offset displayToUv(Offset point) {
    final r = displayRect;
    if (r.width <= 0 || r.height <= 0) return Offset.zero;
    return Offset(
      ((point.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((point.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }
}

/// Official HLO map with draggable pins for each OCR-detected label.
class OcrLabelMapEditor extends StatefulWidget {
  const OcrLabelMapEditor({
    required this.imagePath,
    required this.labels,
    required this.selectedLabelId,
    required this.onLabelSelected,
    required this.onLabelMoved,
    this.compact = false,
    super.key,
  });

  final String imagePath;
  final List<MapTextLabel> labels;
  final String? selectedLabelId;
  final ValueChanged<String> onLabelSelected;
  final void Function(String labelId, double uvX, double uvY) onLabelMoved;
  final bool compact;

  @override
  State<OcrLabelMapEditor> createState() => _OcrLabelMapEditorState();
}

class _OcrLabelMapEditorState extends State<OcrLabelMapEditor> {
  final _stackKey = GlobalKey();
  Size? _imageSize;
  String? _draggingId;

  @override
  void initState() {
    super.initState();
    _loadImageSize();
  }

  @override
  void didUpdateWidget(OcrLabelMapEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) _loadImageSize();
  }

  Future<void> _loadImageSize() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (!mounted || decoded == null) return;
    setState(() => _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble()));
  }

  void _movePin(String labelId, Offset globalPosition, ImageCoordMapper mapper) {
    final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final uv = mapper.displayToUv(local);
    widget.onLabelMoved(labelId, uv.dx, uv.dy);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.compact)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  const Icon(Icons.pin_drop_outlined, size: 16, color: Color(0xFF00E676)),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Tap a pin or list item · drag pins to fix OCR positions',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                  if (_draggingId != null)
                    const Text('Dragging…', style: TextStyle(fontSize: 11, color: Color(0xFF42A5F5))),
                ],
              ),
            ),
          Expanded(
            child: _imageSize == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E676)))
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final mapper = ImageCoordMapper(
                        containerSize: Size(constraints.maxWidth, constraints.maxHeight),
                        imageSize: _imageSize!,
                      );
                      final rect = mapper.displayRect;

                      return Stack(
                        key: _stackKey,
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fromRect(
                            rect: rect,
                            child: Image.file(File(widget.imagePath), fit: BoxFit.fill),
                          ),
                          for (final label in widget.labels)
                            _DraggablePin(
                              label: label,
                              selected: label.id == widget.selectedLabelId,
                              position: mapper.uvToDisplay(label.uvX, label.uvY),
                              compact: widget.compact,
                              onTap: () => widget.onLabelSelected(label.id),
                              onDragStart: () => setState(() {
                                _draggingId = label.id;
                                widget.onLabelSelected(label.id);
                              }),
                              onDragUpdate: (global) => _movePin(label.id, global, mapper),
                              onDragEnd: () => setState(() => _draggingId = null),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DraggablePin extends StatelessWidget {
  const _DraggablePin({
    required this.label,
    required this.selected,
    required this.position,
    required this.compact,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final MapTextLabel label;
  final bool selected;
  final bool compact;
  final Offset position;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  static double pinSize(bool compact) => compact ? 22.0 : 28.0;

  @override
  Widget build(BuildContext context) {
    final size = pinSize(compact);
    return Positioned(
      left: position.dx - size / 2,
      top: position.dy - size,
      child: GestureDetector(
        onTap: onTap,
        onPanStart: (_) => onDragStart(),
        onPanUpdate: (d) => onDragUpdate(d.globalPosition),
        onPanEnd: (_) => onDragEnd(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected && !compact)
              Container(
                constraints: const BoxConstraints(maxWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00E676)),
                ),
                child: Text(
                  label.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            Icon(
              Icons.location_on,
              size: size,
              color: selected ? const Color(0xFF00E676) : const Color(0xFF42A5F5),
              shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ],
        ),
      ),
    );
  }
}
