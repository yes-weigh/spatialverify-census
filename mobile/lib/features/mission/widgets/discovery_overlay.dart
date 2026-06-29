import 'package:flutter/material.dart';

import '../models/discovery_models.dart';

/// Structure/landmark overlays — no roads, no confidence scores.
class DiscoveryOverlay extends StatelessWidget {
  const DiscoveryOverlay({
    required this.candidates,
    required this.onQuickConfirm,
    required this.onOpenDetails,
    super.key,
  });

  final List<DiscoveryCandidate> candidates;
  final void Function(DiscoveryCandidate) onQuickConfirm;
  final void Function(DiscoveryCandidate) onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final visible = candidates.where((c) => c.showOnCamera).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: visible.map((c) => _CandidateBox(
                candidate: c,
                maxWidth: constraints.maxWidth,
                maxHeight: constraints.maxHeight,
                onTap: () => onQuickConfirm(c),
                onLongPress: () => onOpenDetails(c),
              ),).toList(),
        );
      },
    );
  }
}

class _CandidateBox extends StatefulWidget {
  const _CandidateBox({
    required this.candidate,
    required this.maxWidth,
    required this.maxHeight,
    required this.onTap,
    required this.onLongPress,
  });

  final DiscoveryCandidate candidate;
  final double maxWidth;
  final double maxHeight;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_CandidateBox> createState() => _CandidateBoxState();
}

class _CandidateBoxState extends State<_CandidateBox> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.candidate;
    final box = c.boundingBox;
    final left = box.x * widget.maxWidth;
    final top = box.y * widget.maxHeight;
    final width = box.width * widget.maxWidth;
    final height = box.height * widget.maxHeight;
    final color = _outlineColor(c);
    final isPulsing = c.status == DiscoveryCandidateStatus.suggested;

    Widget border = Container(
      decoration: BoxDecoration(
        border: Border.all(color: color, width: c.status == DiscoveryCandidateStatus.confirmed ? 3 : 2),
        borderRadius: BorderRadius.circular(6),
        color: color.withValues(alpha: c.status == DiscoveryCandidateStatus.confirmed ? 0.15 : 0.08),
      ),
    );

    if (isPulsing) {
      border = AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) {
          final glow = 0.3 + _pulse.value * 0.4;
          return Container(
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: glow + 0.4), width: 2.5),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: color.withValues(alpha: glow * 0.5), blurRadius: 8)],
            ),
            child: child,
          );
        },
        child: border,
      );
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            border,
            Positioned(
              top: -24,
              left: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  c.typeLabel,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (isPulsing)
              Positioned(
                bottom: -18,
                left: 0,
                child: Text(
                  'Tap confirm · Hold details',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 8),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _outlineColor(DiscoveryCandidate c) {
    if (c.status == DiscoveryCandidateStatus.confirmed) return const Color(0xFF00E676);
    if (c.status == DiscoveryCandidateStatus.rejected) return const Color(0xFF757575);
    switch (c.type) {
      case DiscoveryObjectType.landmark:
        return const Color(0xFFCE93D8);
      case DiscoveryObjectType.building:
      case DiscoveryObjectType.road:
        return const Color(0xFF42A5F5);
    }
  }
}
